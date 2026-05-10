/**
 * @description Data Transfer Objects for the Open-Meteo Weather API integration.
 *
 * Contains inner classes that mirror the JSON structure of both API responses,
 * plus a unified {@link WeatherResult} wrapper that is exposed to Lightning Web Components.
 * All field names match the API JSON keys exactly to allow direct JSON.deserialize() mapping.
 */
public with sharing class WeatherDTO {

    // ── Geocoding API ──────────────────────────────────────────────────────────

    /**
     * @description Top-level response envelope from the Open-Meteo Geocoding API.
     * Example endpoint: GET https://geocoding-api.open-meteo.com/v1/search?name=London&count=1
     */
    public class GeocodingResponse {
        /** List of matching locations. Empty when no city is found. */
        public List<GeocodingResult> results;
    }

    /**
     * @description A single resolved city from the Geocoding API.
     * Fields are annotated with @AuraEnabled so this type can be returned
     * directly from @AuraEnabled Apex methods called by LWC.
     */
    public class GeocodingResult {
        @AuraEnabled public String  name;
        @AuraEnabled public Decimal latitude;
        @AuraEnabled public Decimal longitude;
        @AuraEnabled public String  country;
        @AuraEnabled public String  country_code;
        @AuraEnabled public String  timezone;
        @AuraEnabled public String  admin1;
    }

    // ── Forecast API ───────────────────────────────────────────────────────────

    /**
     * @description Top-level response envelope from the Open-Meteo Forecast API.
     * Example endpoint: GET https://api.open-meteo.com/v1/forecast?latitude=-23.5&longitude=-46.6&current=...
     */
    public class ForecastResponse {
        /** Current weather observation block. */
        public CurrentWeather current;
        /** Unit labels corresponding to each field in {@link CurrentWeather}. */
        public CurrentWeatherUnits current_units;
    }

    /**
     * @description Current weather observation values returned by the Forecast API.
     * Each field name corresponds exactly to the API parameter name requested via &current=...
     */
    public class CurrentWeather {
        public String  currentTime;
        public Integer interval;
        public Decimal temperature_2m;
        public Decimal apparent_temperature;
        public Integer relative_humidity_2m;
        public Decimal wind_speed_10m;
        public Decimal precipitation;
        public Integer weather_code;
    }

    /**
     * @description Unit strings for each weather field (e.g. "°C", "km/h", "%").
     */
    public class CurrentWeatherUnits {
        public String temperature_2m;
        public String apparent_temperature;
        public String relative_humidity_2m;
        public String wind_speed_10m;
        public String precipitation;
    }

    // ── LWC Result ─────────────────────────────────────────────────────────────

    /**
     * @description Unified weather result returned to the Lightning Web Component.
     * Combines geocoding and forecast data into a single flat structure,
     * with human-readable description and icon fields derived from WMO weather codes.
     */
    public class WeatherResult {
        @AuraEnabled public String  cityName;
        @AuraEnabled public String  countryCode;
        @AuraEnabled public String  timezone;
        @AuraEnabled public Decimal temperature;
        @AuraEnabled public String  temperatureUnit;
        @AuraEnabled public Decimal feelsLike;
        @AuraEnabled public Integer humidity;
        @AuraEnabled public String  humidityUnit;
        @AuraEnabled public Decimal windSpeed;
        @AuraEnabled public String  windSpeedUnit;
        @AuraEnabled public Decimal precipitation;
        @AuraEnabled public String  precipitationUnit;
        @AuraEnabled public Integer weatherCode;
        @AuraEnabled public String  weatherDescription;
        @AuraEnabled public String  weatherIcon;
        @AuraEnabled public String  observationTime;
    }
}
