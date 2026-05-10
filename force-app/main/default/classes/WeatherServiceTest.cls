/**
 * @description Unit tests for {@link WeatherService}.
 *
 * All HTTP callouts are intercepted via {@link HttpCalloutMock} implementations.
 * Config is injected via {@link WeatherService.testConfig} to keep tests hermetic
 * and independent of Custom Metadata deployment state in the org.
 *
 * Coverage target: ≥ 85%
 */
@isTest
private class WeatherServiceTest {

    // ── Fixtures ───────────────────────────────────────────────────────────────

    private static final String GEOCODING_SUCCESS_JSON =
        '{"results":[{"name":"London","latitude":51.5074,"longitude":-0.1278,' +
        '"country":"United Kingdom","country_code":"GB","timezone":"Europe/London","admin1":"England"}]}';

    private static final String GEOCODING_EMPTY_JSON = '{"results":[]}';

    private static final String FORECAST_SUCCESS_JSON =
        '{"current_units":{"temperature_2m":"°C","apparent_temperature":"°C",' +
        '"relative_humidity_2m":"%","wind_speed_10m":"km/h","precipitation":"mm"},' +
        '"current":{"time":"2024-05-10T14:00","interval":900,"temperature_2m":18.5,' +
        '"apparent_temperature":16.8,"relative_humidity_2m":62,"wind_speed_10m":14.2,' +
        '"precipitation":0.0,"weather_code":2}}';

    private static WeatherAPIConfig__mdt makeConfig() {
        return new WeatherAPIConfig__mdt(
            GeocodingEndpoint__c     = 'https://geocoding-api.open-meteo.com/v1/search',
            ForecastEndpoint__c      = 'https://api.open-meteo.com/v1/forecast',
            ForecastCurrentParams__c = 'temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,precipitation,weather_code',
            Timeout__c               = 10000
        );
    }

    // ── Mock Implementations ───────────────────────────────────────────────────

    /** Returns a fixed response body with HTTP 200. */
    private class SingleMock implements HttpCalloutMock {
        private final String  body;
        private final Integer status;
        SingleMock(String body, Integer status) { this.body = body; this.status = status; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setBody(this.body);
            res.setStatusCode(this.status);
            res.setStatus(this.status == 200 ? 'OK' : 'Error');
            return res;
        }
    }

    /** Serves responses in order for multi-callout flows (geocoding → forecast). */
    private class MultiMock implements HttpCalloutMock {
        private final List<HttpResponse> queue = new List<HttpResponse>();
        private Integer idx = 0;
        MultiMock addResponse(String body, Integer status) {
            HttpResponse r = new HttpResponse();
            r.setBody(body);
            r.setStatusCode(status);
            r.setStatus(status == 200 ? 'OK' : 'Error');
            queue.add(r);
            return this;
        }
        public HttpResponse respond(HttpRequest req) { return queue[idx++]; }
    }

    /** Simulates a network-level callout failure. */
    private class ErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Simulated network error');
        }
    }

    // ── geocodeCity ────────────────────────────────────────────────────────────

    @isTest
    static void testGeocodeCity_success() {
        WeatherService.testConfig = makeConfig();
        Test.setMock(HttpCalloutMock.class, new SingleMock(GEOCODING_SUCCESS_JSON, 200));

        Test.startTest();
        WeatherDTO.GeocodingResult result = WeatherService.geocodeCity('London');
        Test.stopTest();

        System.assertEquals('London', result.name, 'City name should match');
        System.assertEquals(51.5074, result.latitude, 'Latitude should match');
        System.assertEquals(-0.1278, result.longitude, 'Longitude should match');
        System.assertEquals('GB', result.country_code, 'Country code should match');
        System.assertEquals('Europe/London', result.timezone, 'Timezone should match');
    }

    @isTest
    static void testGeocodeCity_blankInput_throws() {
        WeatherService.testConfig = makeConfig();

        Test.startTest();
        try {
            WeatherService.geocodeCity('   ');
            System.assert(false, 'Expected WeatherServiceException for blank input');
        } catch (WeatherService.WeatherServiceException e) {
            System.assert(e.getMessage().contains('vazio'), 'Message should mention empty: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testGeocodeCity_notFound_throws() {
        WeatherService.testConfig = makeConfig();
        Test.setMock(HttpCalloutMock.class, new SingleMock(GEOCODING_EMPTY_JSON, 200));

        Test.startTest();
        try {
            WeatherService.geocodeCity('XyzNonExistentCity999');
            System.assert(false, 'Expected WeatherServiceException for unknown city');
        } catch (WeatherService.WeatherServiceException e) {
            System.assert(e.getMessage().contains('não encontrada'), 'Message should mention not found: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testGeocodeCity_httpError_throws() {
        WeatherService.testConfig = makeConfig();
        Test.setMock(HttpCalloutMock.class, new SingleMock('Internal Server Error', 500));

        Test.startTest();
        try {
            WeatherService.geocodeCity('London');
            System.assert(false, 'Expected WeatherServiceException for HTTP 500');
        } catch (WeatherService.WeatherServiceException e) {
            System.assert(e.getMessage().contains('500'), 'Message should contain status code: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testGeocodeCity_calloutException_throws() {
        WeatherService.testConfig = makeConfig();
        Test.setMock(HttpCalloutMock.class, new ErrorMock());

        Test.startTest();
        try {
            WeatherService.geocodeCity('London');
            System.assert(false, 'Expected WeatherServiceException for callout error');
        } catch (WeatherService.WeatherServiceException e) {
            System.assert(e.getMessage().contains('chamada externa'), 'Message should mention callout failure: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testGeocodeCity_invalidJson_throws() {
        WeatherService.testConfig = makeConfig();
        Test.setMock(HttpCalloutMock.class, new SingleMock('NOT_VALID_JSON!!!', 200));

        Test.startTest();
        try {
            WeatherService.geocodeCity('London');
            System.assert(false, 'Expected WeatherServiceException for invalid JSON');
        } catch (WeatherService.WeatherServiceException e) {
            System.assert(e.getMessage().contains('processar'), 'Message should mention processar: ' + e.getMessage());
        }
        Test.stopTest();
    }

    // ── getWeatherByCity ───────────────────────────────────────────────────────

    @isTest
    static void testGetWeatherByCity_success() {
        WeatherService.testConfig = makeConfig();
        Test.setMock(HttpCalloutMock.class,
            new MultiMock()
                .addResponse(GEOCODING_SUCCESS_JSON, 200)
                .addResponse(FORECAST_SUCCESS_JSON, 200)
        );

        Test.startTest();
        WeatherDTO.WeatherResult r = WeatherService.getWeatherByCity('London');
        Test.stopTest();

        System.assertEquals('London',         r.cityName,          'City name');
        System.assertEquals('GB',             r.countryCode,       'Country code');
        System.assertEquals('Europe/London',  r.timezone,          'Timezone');
        System.assertEquals(18.5,             r.temperature,       'Temperature');
        System.assertEquals('°C',             r.temperatureUnit,   'Temp unit');
        System.assertEquals(16.8,             r.feelsLike,         'Feels like');
        System.assertEquals(62,               r.humidity,          'Humidity');
        System.assertEquals('%',              r.humidityUnit,      'Humidity unit');
        System.assertEquals(14.2,             r.windSpeed,         'Wind speed');
        System.assertEquals('km/h',           r.windSpeedUnit,     'Wind unit');
        System.assertEquals(0.0,              r.precipitation,     'Precipitation');
        System.assertEquals(2,                r.weatherCode,       'Weather code');
        System.assertEquals('Parcialmente Nublado', r.weatherDescription, 'Description');
        System.assertEquals('🌤️',            r.weatherIcon,       'Icon');
        System.assertNotEquals(null,           r.observationTime,   'Observation time');
    }

    @isTest
    static void testGetWeatherByCity_forecastHttpError_throws() {
        WeatherService.testConfig = makeConfig();
        Test.setMock(HttpCalloutMock.class,
            new MultiMock()
                .addResponse(GEOCODING_SUCCESS_JSON, 200)
                .addResponse('Service Unavailable', 503)
        );

        Test.startTest();
        try {
            WeatherService.getWeatherByCity('London');
            System.assert(false, 'Expected WeatherServiceException for forecast HTTP error');
        } catch (WeatherService.WeatherServiceException e) {
            System.assert(e.getMessage().contains('503'), 'Message should contain 503: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testGetWeatherByCity_forecastInvalidJson_throws() {
        WeatherService.testConfig = makeConfig();
        Test.setMock(HttpCalloutMock.class,
            new MultiMock()
                .addResponse(GEOCODING_SUCCESS_JSON, 200)
                .addResponse('CORRUPTED_JSON', 200)
        );

        Test.startTest();
        try {
            WeatherService.getWeatherByCity('London');
            System.assert(false, 'Expected WeatherServiceException for bad forecast JSON');
        } catch (WeatherService.WeatherServiceException e) {
            System.assert(e.getMessage().contains('processar'), 'Message should mention processar: ' + e.getMessage());
        }
        Test.stopTest();
    }

    // ── WMO Code Helpers ───────────────────────────────────────────────────────

    @isTest
    static void testGetWMODescription_allBranches() {
        System.assertEquals('Céu Limpo',                  WeatherService.getWMODescription(0));
        System.assertEquals('Predominantemente Limpo',    WeatherService.getWMODescription(1));
        System.assertEquals('Parcialmente Nublado',       WeatherService.getWMODescription(2));
        System.assertEquals('Encoberto',                  WeatherService.getWMODescription(3));
        System.assertEquals('Neblina',                    WeatherService.getWMODescription(45));
        System.assertEquals('Neblina',                    WeatherService.getWMODescription(48));
        System.assertEquals('Garoa',                      WeatherService.getWMODescription(51));
        System.assertEquals('Garoa',                      WeatherService.getWMODescription(55));
        System.assertEquals('Garoa Congelante',           WeatherService.getWMODescription(56));
        System.assertEquals('Garoa Congelante',           WeatherService.getWMODescription(57));
        System.assertEquals('Chuva',                      WeatherService.getWMODescription(61));
        System.assertEquals('Chuva',                      WeatherService.getWMODescription(65));
        System.assertEquals('Chuva Congelante',           WeatherService.getWMODescription(66));
        System.assertEquals('Neve',                       WeatherService.getWMODescription(71));
        System.assertEquals('Grãos de Neve',              WeatherService.getWMODescription(77));
        System.assertEquals('Pancadas de Chuva',          WeatherService.getWMODescription(80));
        System.assertEquals('Pancadas de Chuva',          WeatherService.getWMODescription(82));
        System.assertEquals('Pancadas de Neve',           WeatherService.getWMODescription(85));
        System.assertEquals('Tempestade',                 WeatherService.getWMODescription(95));
        System.assertEquals('Tempestade com Granizo',     WeatherService.getWMODescription(96));
        System.assertEquals('Tempestade com Granizo',     WeatherService.getWMODescription(99));
        System.assertEquals('Desconhecido',               WeatherService.getWMODescription(null));
        System.assertEquals('Desconhecido',               WeatherService.getWMODescription(999));
    }

    @isTest
    static void testGetWMOIcon_allBranches() {
        System.assertEquals('☀️',  WeatherService.getWMOIcon(0));
        System.assertEquals('🌤️', WeatherService.getWMOIcon(1));
        System.assertEquals('🌤️', WeatherService.getWMOIcon(2));
        System.assertEquals('☁️',  WeatherService.getWMOIcon(3));
        System.assertEquals('🌫️', WeatherService.getWMOIcon(45));
        System.assertEquals('🌦️', WeatherService.getWMOIcon(51));
        System.assertEquals('🌧️', WeatherService.getWMOIcon(61));
        System.assertEquals('❄️',  WeatherService.getWMOIcon(71));
        System.assertEquals('🌧️', WeatherService.getWMOIcon(80));
        System.assertEquals('🌨️', WeatherService.getWMOIcon(85));
        System.assertEquals('⛈️',  WeatherService.getWMOIcon(95));
        System.assertEquals('❓',   WeatherService.getWMOIcon(null));
        System.assertEquals('🌡️', WeatherService.getWMOIcon(40));
    }
}
