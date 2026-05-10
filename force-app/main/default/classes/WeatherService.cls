/**
 * @description Service class for the Open-Meteo Weather API integration.
 *
 * Responsibilities:
 * - {@link geocodeCity}: resolves a city name to geographic coordinates via the Geocoding API.
 * - {@link getWeatherByCity}: orchestrates geocoding + forecast retrieval and returns
 *   a unified {@link WeatherDTO.WeatherResult} ready for display in LWC.
 *
 * All API configuration (endpoints, parameters, timeout) is read from
 * {@link WeatherAPIConfig__mdt} Custom Metadata — no values are hardcoded in this class.
 */
public with sharing class WeatherService {

    private static WeatherAPIConfig__mdt config;

    /**
     * Allows unit tests to inject a synthetic config record without querying the org,
     * making tests hermetic and independent of CMT deployment state.
     */
    @testVisible
    private static WeatherAPIConfig__mdt testConfig;

    // ── Config Loading ─────────────────────────────────────────────────────────

    private static WeatherAPIConfig__mdt getConfig() {
        if (testConfig != null) return testConfig;
        if (config != null) return config;
        config = fetchConfig();
        return config;
    }

    private static WeatherAPIConfig__mdt fetchConfig() {
        List<WeatherAPIConfig__mdt> records = [
            SELECT GeocodingEndpoint__c, ForecastEndpoint__c,
                   ForecastCurrentParams__c, Timeout__c
            FROM WeatherAPIConfig__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        if (records.isEmpty()) {
            throw new WeatherServiceException(
                'Registro "Default" do WeatherAPIConfig__mdt não encontrado. Faça o deploy do Custom Metadata antes de usar este serviço.'
            );
        }
        return records[0];
    }

    // ── Public API ─────────────────────────────────────────────────────────────

    /**
     * @description Resolves a city name to its geographic coordinates using the Open-Meteo Geocoding API.
     *
     * @param cityName The city name to search for (e.g. "São Paulo", "London").
     * @return A {@link WeatherDTO.GeocodingResult} with latitude, longitude, country, and timezone.
     * @throws WeatherServiceException if the city is not found, the callout fails, or the response is malformed.
     */
    @AuraEnabled
    public static WeatherDTO.GeocodingResult geocodeCity(String cityName) {
        if (String.isBlank(cityName)) {
            throw new WeatherServiceException('O nome da cidade não pode estar vazio.');
        }

        WeatherAPIConfig__mdt cfg = getConfig();
        String endpoint = cfg.GeocodingEndpoint__c
            + '?name=' + EncodingUtil.urlEncode(cityName.trim(), 'UTF-8')
            + '&count=1&language=en&format=json';

        HttpResponse res = doCallout(endpoint, Integer.valueOf(cfg.Timeout__c));

        WeatherDTO.GeocodingResponse parsed;
        try {
            parsed = (WeatherDTO.GeocodingResponse) JSON.deserialize(
                res.getBody(), WeatherDTO.GeocodingResponse.class
            );
        } catch (Exception e) {
            throw new WeatherServiceException('Falha ao processar resposta de geocoding: ' + e.getMessage());
        }

        if (parsed == null || parsed.results == null || parsed.results.isEmpty()) {
            throw new WeatherServiceException('Cidade não encontrada: "' + cityName + '". Tente uma grafia diferente ou uma cidade próxima.');
        }

        return parsed.results[0];
    }

    /**
     * @description Main LWC entry point — resolves a city name and returns its current weather.
     *
     * Internally calls {@link geocodeCity} then the Forecast API, combining both results
     * into a single {@link WeatherDTO.WeatherResult}.
     *
     * @param cityName The city to fetch weather for.
     * @return A {@link WeatherDTO.WeatherResult} with all climate fields populated.
     * @throws WeatherServiceException on any callout or parsing failure.
     */
    @AuraEnabled
    public static WeatherDTO.WeatherResult getWeatherByCity(String cityName) {
        WeatherDTO.GeocodingResult location = geocodeCity(cityName);
        WeatherDTO.ForecastResponse forecast = fetchForecast(location.latitude, location.longitude);
        return buildWeatherResult(location, forecast);
    }

    // ── Private Helpers ────────────────────────────────────────────────────────

    private static WeatherDTO.ForecastResponse fetchForecast(Decimal latitude, Decimal longitude) {
        WeatherAPIConfig__mdt cfg = getConfig();
        String endpoint = cfg.ForecastEndpoint__c
            + '?latitude='  + latitude
            + '&longitude=' + longitude
            + '&current='   + cfg.ForecastCurrentParams__c
            + '&timezone=auto&format=json';

        HttpResponse res = doCallout(endpoint, Integer.valueOf(cfg.Timeout__c));

        try {
            // 'time' is a reserved Apex identifier; remap JSON key before deserialization
            String body = res.getBody().replace('"time":', '"currentTime":');
            return (WeatherDTO.ForecastResponse) JSON.deserialize(
                body, WeatherDTO.ForecastResponse.class
            );
        } catch (Exception e) {
            throw new WeatherServiceException('Falha ao processar resposta de previsão: ' + e.getMessage());
        }
    }

    private static HttpResponse doCallout(String endpoint, Integer timeoutMs) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(timeoutMs);

        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (CalloutException e) {
            throw new WeatherServiceException('Falha na chamada externa: ' + e.getMessage());
        }

        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new WeatherServiceException(
                'Erro na API — HTTP ' + res.getStatusCode() + ' ' + res.getStatus()
            );
        }
        return res;
    }

    private static WeatherDTO.WeatherResult buildWeatherResult(
        WeatherDTO.GeocodingResult location,
        WeatherDTO.ForecastResponse forecast
    ) {
        WeatherDTO.CurrentWeather    cw = forecast.current;
        WeatherDTO.CurrentWeatherUnits cu = forecast.current_units;

        WeatherDTO.WeatherResult r = new WeatherDTO.WeatherResult();
        r.cityName          = location.name;
        r.countryCode       = location.country_code;
        r.timezone          = location.timezone;
        r.temperature       = cw.temperature_2m;
        r.temperatureUnit   = cu != null ? cu.temperature_2m      : '°C';
        r.feelsLike         = cw.apparent_temperature;
        r.humidity          = cw.relative_humidity_2m;
        r.humidityUnit      = cu != null ? cu.relative_humidity_2m : '%';
        r.windSpeed         = cw.wind_speed_10m;
        r.windSpeedUnit     = cu != null ? cu.wind_speed_10m       : 'km/h';
        r.precipitation     = cw.precipitation;
        r.precipitationUnit = cu != null ? cu.precipitation        : 'mm';
        r.weatherCode       = cw.weather_code;
        r.weatherDescription = getWMODescription(cw.weather_code);
        r.weatherIcon        = getWMOIcon(cw.weather_code);
        r.observationTime    = cw.currentTime;
        return r;
    }

    /**
     * @description Maps a WMO weather interpretation code to a human-readable description.
     * @see https://open-meteo.com/en/docs#weathervariables (WMO Weather interpretation codes)
     */
    @testVisible
    private static String getWMODescription(Integer code) {
        if (code == null)                       return 'Desconhecido';
        if (code == 0)                          return 'Céu Limpo';
        if (code == 1)                          return 'Predominantemente Limpo';
        if (code == 2)                          return 'Parcialmente Nublado';
        if (code == 3)                          return 'Encoberto';
        if (code == 45 || code == 48)           return 'Neblina';
        if (code >= 51 && code <= 55)           return 'Garoa';
        if (code == 56 || code == 57)           return 'Garoa Congelante';
        if (code >= 61 && code <= 65)           return 'Chuva';
        if (code == 66 || code == 67)           return 'Chuva Congelante';
        if (code >= 71 && code <= 75)           return 'Neve';
        if (code == 77)                         return 'Grãos de Neve';
        if (code >= 80 && code <= 82)           return 'Pancadas de Chuva';
        if (code == 85 || code == 86)           return 'Pancadas de Neve';
        if (code == 95)                         return 'Tempestade';
        if (code == 96 || code == 99)           return 'Tempestade com Granizo';
        return 'Desconhecido';
    }

    /**
     * @description Maps a WMO weather code to an emoji icon for display in the LWC.
     */
    @testVisible
    private static String getWMOIcon(Integer code) {
        if (code == null)                       return '❓';
        if (code == 0)                          return '☀️';
        if (code <= 2)                          return '🌤️';
        if (code == 3)                          return '☁️';
        if (code == 45 || code == 48)           return '🌫️';
        if (code >= 51 && code <= 57)           return '🌦️';
        if (code >= 61 && code <= 67)           return '🌧️';
        if (code >= 71 && code <= 77)           return '❄️';
        if (code >= 80 && code <= 82)           return '🌧️';
        if (code == 85 || code == 86)           return '🌨️';
        if (code >= 95)                         return '⛈️';
        return '🌡️';
    }

    /** @description Thrown when geocoding, forecast, or parsing fails. */
    public class WeatherServiceException extends Exception {}
}
