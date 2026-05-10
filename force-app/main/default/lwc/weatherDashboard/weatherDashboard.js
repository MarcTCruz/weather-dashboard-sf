/**
 * @description Controller for the Weather Dashboard LWC.
 *
 * Calls {@link WeatherService.getWeatherByCity} imperatively (user-driven search),
 * manages loading, error, and result states, and derives display-ready
 * values from the Apex response.
 *
 * @module weatherDashboard
 */
import { LightningElement, track } from 'lwc';
import getWeatherByCity from '@salesforce/apex/WeatherService.getWeatherByCity';

export default class WeatherDashboard extends LightningElement {

    /** @type {string} Current value of the city search input. */
    @track cityName = '';

    /** @type {WeatherDTO.WeatherResult|null} Last successful API response. */
    @track weatherData = null;

    /** @type {boolean} True while an Apex callout is in-flight. */
    @track isLoading = false;

    /** @type {string} User-facing error message; empty string when no error. */
    @track errorMessage = '';

    // ── Derived State ──────────────────────────────────────────────────────────

    /** @returns {boolean} True when an error message should be displayed. */
    get hasError() {
        return this.errorMessage.length > 0;
    }

    /** @returns {boolean} True when the initial empty-state placeholder should show. */
    get showEmptyState() {
        return !this.isLoading && !this.hasError && !this.weatherData;
    }

    /** @returns {boolean} Disables the search button while loading or when input is blank. */
    get isSearchDisabled() {
        return this.isLoading || !this.cityName.trim();
    }

    /**
     * @returns {string} Localised, human-readable observation time.
     * Falls back to the raw ISO string if parsing fails.
     */
    get formattedTime() {
        if (!this.weatherData || !this.weatherData.observationTime) return '';
        try {
            return new Date(this.weatherData.observationTime).toLocaleString(undefined, {
                weekday: 'short', month: 'short', day: 'numeric',
                hour: '2-digit', minute: '2-digit'
            });
        } catch (_) {
            return this.weatherData.observationTime;
        }
    }

    // ── Event Handlers ─────────────────────────────────────────────────────────

    /**
     * @description Keeps {@link cityName} in sync with the input field value.
     * @param {Event} event - Change event from lightning-input.
     */
    handleCityChange(event) {
        this.cityName = event.target.value;
    }

    /**
     * @description Triggers a search when the user presses Enter.
     * @param {KeyboardEvent} event - Keyup event from lightning-input.
     */
    handleKeyUp(event) {
        if (event.key === 'Enter') {
            this.handleSearch();
        }
    }

    /**
     * @description Calls {@link WeatherService.getWeatherByCity} imperatively and
     * updates component state based on the result or any thrown error.
     */
    async handleSearch() {
        const city = this.cityName.trim();
        if (!city) return;

        this.isLoading    = true;
        this.errorMessage = '';
        this.weatherData  = null;

        try {
            this.weatherData = await getWeatherByCity({ cityName: city });
        } catch (error) {
            this.errorMessage = this._extractErrorMessage(error);
        } finally {
            this.isLoading = false;
        }
    }

    // ── Private Helpers ────────────────────────────────────────────────────────

    /**
     * @description Extracts a user-friendly message from various Salesforce error shapes.
     * @param {Object} error - The caught error from an @AuraEnabled Apex call.
     * @returns {string} Human-readable error text.
     */
    _extractErrorMessage(error) {
        if (error?.body?.message)           return error.body.message;
        if (error?.body?.pageErrors?.length) return error.body.pageErrors[0].message;
        if (error?.message)                 return error.message;
        return 'An unexpected error occurred. Please try again.';
    }
}
