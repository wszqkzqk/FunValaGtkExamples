#!/usr/bin/env -S vala --pkg=gio-2.0 --pkg=json-glib-1.0 -X -lm -X -O2 -X -march=native -X -pipe
/* SPDX-License-Identifier: LGPL-2.1-or-later */

/**
 * Day Length Calculator CLI with Auto-Detection and Horizon Correction.
 * Copyright (C) 2025 wszqkzqk <wszqkzqk@qq.com>
 *
 * A command-line tool that calculates day length, sunrise, and sunset times
 * using high-precision astronomical formulas, with optional auto-location
 * and timezone detection.
 */

private const double DEG2RAD = Math.PI / 180.0;
private const double RAD2DEG = 180.0 / Math.PI;

/**
 * Compute solar parameters at a given local time.
 *
 * @param base_days_from_epoch Days from J2000.0 epoch at UTC midnight
 * @param time_local_hours Local time in hours [0,24)
 * @param obliquity_sin Sine of obliquity
 * @param obliquity_cos Cosine of obliquity
 * @param ecliptic_c1 Ecliptic longitude correction coefficient 1
 * @param ecliptic_c2 Ecliptic longitude correction coefficient 2
 */
private static inline void compute_solar_parameters (
    double base_days_from_epoch, double time_local_hours,
    double obliquity_sin, double obliquity_cos,
    double ecliptic_c1, double ecliptic_c2,
    out double out_declination_sin, out double out_declination_cos, out double out_eqtime_minutes
) {
    double days_from_epoch = base_days_from_epoch + time_local_hours / 24.0;
    double days_sq = days_from_epoch * days_from_epoch;
    double days_cb = days_sq * days_from_epoch;

    // Mean anomaly
    double mean_anomaly_deg = 357.52910 + 0.985600282 * days_from_epoch - 1.1686e-13 * days_sq - 9.85e-21 * days_cb;
    double mean_anomaly_rad = mean_anomaly_deg * DEG2RAD;

    // Mean longitude (normalized)
    double mean_longitude_deg = Math.fmod (280.46645 + 0.98564736 * days_from_epoch + 2.2727e-13 * days_sq, 360.0);
    if (mean_longitude_deg < 0) {
        mean_longitude_deg += 360.0;
    }

    // Ecliptic longitude
    double ecliptic_longitude_deg = mean_longitude_deg
        + ecliptic_c1 * Math.sin (mean_anomaly_rad)
        + ecliptic_c2 * Math.sin (2.0 * mean_anomaly_rad)
        + 0.000290 * Math.sin (3.0 * mean_anomaly_rad);

    double ecliptic_longitude_rad = ecliptic_longitude_deg * DEG2RAD;
    double ecliptic_longitude_sin = Math.sin (ecliptic_longitude_rad);
    double ecliptic_longitude_cos = Math.cos (ecliptic_longitude_rad);

    // Declination
    out_declination_sin = (obliquity_sin * ecliptic_longitude_sin).clamp (-1.0, 1.0);
    out_declination_cos = Math.sqrt (1.0 - out_declination_sin * out_declination_sin);

    // Equation of time
    double right_ascension_rad = Math.atan2 (obliquity_cos * ecliptic_longitude_sin, ecliptic_longitude_cos);
    double right_ascension_hours = right_ascension_rad * RAD2DEG / 15.0;
    double mean_time_hours = mean_longitude_deg / 15.0;

    double time_diff = mean_time_hours - right_ascension_hours;
    if (time_diff > 12.0) {
        time_diff -= 24.0;
    } else if (time_diff < -12.0) {
        time_diff += 24.0;
    }
    out_eqtime_minutes = time_diff * 60.0;
}

/**
 * Calculates day length, sunrise, and sunset times.
 * Based on http://www.jgiesen.de/elevaz/basics/meeus.htm
 *
 * @param latitude_rad Latitude in radians.
 * @param longitude_deg Longitude in degrees.
 * @param timezone_offset_hrs Timezone offset in hours from UTC.
 * @param julian_date GLib's Julian Date for the day (from 0001-01-01).
 * @param horizon_angle_deg Horizon angle correction in degrees (default -0.83° for atmospheric refraction).
 * @param day_length Output parameter for day length in hours.
 * @param sunrise_time Output parameter for sunrise time in local hours [0,24).
 * @param sunset_time Output parameter for sunset time in local hours [0,24).
 */
private void calculate_day_length (
    double latitude_rad, double longitude_deg, double timezone_offset_hrs, double julian_date, double horizon_angle_deg,
    out double day_length, out double sunrise_time, out double sunset_time
) {
    double sin_lat = Math.sin (latitude_rad);
    double cos_lat = Math.cos (latitude_rad);
    double sin_horizon = Math.sin (horizon_angle_deg * DEG2RAD);
    // Days from J2000.0 epoch at UTC midnight
    double base_days_from_epoch_utc_midnight = (julian_date - 730120.5) - timezone_offset_hrs / 24.0;

    // Obliquity
    double base_days_sq = base_days_from_epoch_utc_midnight * base_days_from_epoch_utc_midnight;
    double base_days_cb = base_days_sq * base_days_from_epoch_utc_midnight;
    double obliquity_deg = 23.439291111 - 3.560347e-7 * base_days_from_epoch_utc_midnight - 1.2285e-16 * base_days_sq + 1.0335e-20 * base_days_cb;
    double obliquity_sin = Math.sin (obliquity_deg * DEG2RAD);
    double obliquity_cos = Math.cos (obliquity_deg * DEG2RAD);
    // Ecliptic correction coefficients
    double ecliptic_c1 = 1.914600 - 1.3188e-7 * base_days_from_epoch_utc_midnight - 1.049e-14 * base_days_sq;
    double ecliptic_c2 = 0.019993 - 2.7652e-9 * base_days_from_epoch_utc_midnight;
    double tst_offset = 4.0 * longitude_deg - 60.0 * timezone_offset_hrs;

    // Initial estimate at noon
    double declination_sin, declination_cos, eqtime_minutes;
    compute_solar_parameters (
        base_days_from_epoch_utc_midnight, 12.0,
        obliquity_sin, obliquity_cos, ecliptic_c1, ecliptic_c2,
        out declination_sin, out declination_cos, out eqtime_minutes
    );

    double cos_ha = (sin_horizon - sin_lat * declination_sin) / (cos_lat * declination_cos);

    if (cos_ha >= 1.0) {
        day_length = 0.0;
        sunrise_time = double.NAN;
        sunset_time = double.NAN;
        return;
    } else if (cos_ha <= -1.0) {
        day_length = 24.0;
        sunrise_time = double.NAN;
        sunset_time = double.NAN;
        return;
    }

    double ha_deg = Math.acos (cos_ha) * RAD2DEG;
    sunrise_time = 12.0 - ha_deg / 15.0 - (eqtime_minutes + tst_offset) / 60.0;
    sunset_time  = 12.0 + ha_deg / 15.0 - (eqtime_minutes + tst_offset) / 60.0;

    // Iterative refinement
    const double TOL_HOURS = 0.1 / 3600.0;
    for (int iter = 0; iter < 5; iter += 1) {
        double old_sr = sunrise_time;
        double old_ss = sunset_time;

        compute_solar_parameters (
            base_days_from_epoch_utc_midnight, sunrise_time,
            obliquity_sin, obliquity_cos, ecliptic_c1, ecliptic_c2,
            out declination_sin, out declination_cos, out eqtime_minutes
        );

        cos_ha = (sin_horizon - sin_lat * declination_sin) / (cos_lat * declination_cos);
        if (cos_ha >= 1.0 || cos_ha <= -1.0) {
            break;
        }

        ha_deg = Math.acos (cos_ha) * RAD2DEG;
        sunrise_time = 12.0 - ha_deg / 15.0 - (eqtime_minutes + tst_offset) / 60.0;

        compute_solar_parameters (
            base_days_from_epoch_utc_midnight, sunset_time,
            obliquity_sin, obliquity_cos, ecliptic_c1, ecliptic_c2,
            out declination_sin, out declination_cos, out eqtime_minutes
        );

        cos_ha = (sin_horizon - sin_lat * declination_sin) / (cos_lat * declination_cos);
        if (cos_ha >= 1.0 || cos_ha <= -1.0) {
            break;
        }

        ha_deg = Math.acos (cos_ha) * RAD2DEG;
        sunset_time = 12.0 + ha_deg / 15.0 - (eqtime_minutes + tst_offset) / 60.0;

        if (Math.fabs (sunrise_time - old_sr) < TOL_HOURS && Math.fabs (sunset_time - old_ss) < TOL_HOURS) {
            break;
        }
    }

    // Normalize to [0, 24)
    sunrise_time = Math.fmod (sunrise_time, 24.0);
    if (sunrise_time < 0) {
        sunrise_time += 24.0;
    }
    sunset_time = Math.fmod (sunset_time, 24.0);
    if (sunset_time < 0) {
        sunset_time += 24.0;
    }
    day_length = sunset_time - sunrise_time;
    if (day_length < 0) {
        day_length += 24.0;
    }
}

/**
 * Asynchronously gets current location and timezone using IP geolocation service.
 */
private async void get_location_and_time_async (out double latitude_deg, out double longitude_deg, out double timezone_offset_hours) throws IOError {
    var file = File.new_for_uri ("https://ipapi.co/json/");
    var parser = new Json.Parser ();

    var cancellable = new Cancellable ();
    var timeout_id = Timeout.add_seconds_once (5, () => {
        cancellable.cancel ();
    });

    try {
        var stream = yield file.read_async (Priority.DEFAULT, cancellable);
        yield parser.load_from_stream_async (stream, cancellable);
    } catch (Error e) {
        throw new IOError.FAILED ("Failed to get location: %s", e.message);
    } finally {
        if (!cancellable.is_cancelled ()) {
            Source.remove (timeout_id);
        }
    }

    var root_object = parser.get_root ().get_object ();
    if (root_object.get_boolean_member_with_default ("error", false)) {
        throw new IOError.FAILED ("Location service error: %s",
            root_object.get_string_member_with_default ("reason", "Unknown error"));
    }

    if (root_object.has_member ("latitude") && root_object.has_member ("longitude")) {
        latitude_deg = root_object.get_double_member ("latitude");
        longitude_deg = root_object.get_double_member ("longitude");
    } else {
        throw new IOError.FAILED ("No coordinates found in the response");
    }

    double network_tz_offset = 0.0;
    bool has_network_tz = false;

    if (root_object.has_member ("utc_offset")) {
        var offset_str = root_object.get_string_member ("utc_offset");
        if (double.try_parse(offset_str, out network_tz_offset)) {
            network_tz_offset /= 100.0;
            has_network_tz = true;
        }
    }

    var timezone = new TimeZone.local ();
    var time_interval = timezone.find_interval (GLib.TimeType.UNIVERSAL, new DateTime.now_utc().to_unix ());
    var local_tz_offset = timezone.get_offset (time_interval) / 3600.0;

    const double TZ_EPSILON = 0.01;
    if (has_network_tz && Math.fabs(network_tz_offset - local_tz_offset) > TZ_EPSILON) {
        stderr.printf ("Timezone Mismatch Detected:\n");
        stderr.printf (" - Network-detected timezone: UTC%+.2f\n", network_tz_offset);
        stderr.printf (" - Your system's timezone:  UTC%+.2f\n", local_tz_offset);
        stderr.printf ("Which one would you like to use? [S]ystem (default) / [N]etwork: ");

        string? choice = stdin.read_line ();
        if (choice != null && choice.strip().down() == "n") {
            timezone_offset_hours = network_tz_offset;
            stderr.printf ("Using Network timezone.\n\n");
        } else {
            timezone_offset_hours = local_tz_offset;
            stderr.printf ("Using System timezone.\n\n");
        }
    } else {
        timezone_offset_hours = local_tz_offset;
    }
}

/**
 * Formats time in hours to a HH:MM:SS string.
 */
private static string format_time (double time_in_hours) {
    if (time_in_hours.is_nan()) {
        return "N/A";
    }
    int total_seconds = (int) (time_in_hours * 3600.0);
    int hours = total_seconds / 3600;
    int minutes = (total_seconds % 3600) / 60;
    int seconds = total_seconds % 60;
    return "%02d:%02d:%02d".printf(hours, minutes, seconds);
}

/**
 * Main entry point.
 */
public static async int main (string[] args) {
    Intl.setlocale ();
    double latitude_deg = double.NAN;
    double longitude_deg = double.NAN;
    double timezone_hrs = double.NAN;
    string? date_str = null;
    double horizon_deg = -0.83;

    OptionEntry[] entries = {
        { "latitude", 'l', OptionFlags.NONE, OptionArg.DOUBLE, out latitude_deg,
          "Latitude (-90 to 90). If not set, auto-detects via IP.", "DEG" },
        { "longitude", 'o', OptionFlags.NONE, OptionArg.DOUBLE, out longitude_deg,
          "Longitude (-180 to 180). If not set, auto-detects via IP.", "DEG" },
        { "timezone", 't', OptionFlags.NONE, OptionArg.DOUBLE, out timezone_hrs,
          "Timezone offset from UTC (-12 to 14). If not set, uses local or detected.", "HOURS" },
        { "date", 'd', OptionFlags.NONE, OptionArg.STRING, out date_str,
          "Date (YYYY-MM-DD), defaults to today.", "DATE" },
        { "horizon", '\0', OptionFlags.NONE, OptionArg.DOUBLE, out horizon_deg,
          "Horizon angle in degrees (default: -0.83 for refraction).", "DEG" },
        null
    };

    var context = new OptionContext ("- Calculate daylight duration, sunrise and sunset times");
    context.add_main_entries (entries, null);

    try {
        context.parse (ref args);
    } catch (Error e) {
        printerr ("Error parsing arguments: %s\n", e.message);
        return 1;
    }

    // Auto-detect if any location/timezone parameter is missing
    if (latitude_deg.is_nan () || longitude_deg.is_nan () || timezone_hrs.is_nan ()) {
        try {
            printerr ("Auto-detecting location and timezone...\n");
            double detected_lat, detected_lon, detected_tz;
            yield get_location_and_time_async (out detected_lat, out detected_lon, out detected_tz);

            // Use detected values only if not provided by user
            if (latitude_deg.is_nan ()) {
                latitude_deg = detected_lat;
            }
            if (longitude_deg.is_nan ()) {
                longitude_deg = detected_lon;
            }
            if (timezone_hrs.is_nan ()) {
                timezone_hrs = detected_tz;
            }

            printerr ("Using -> Lat: %.2f°, Lon: %.2f°, TZ: UTC%+.2f\n", latitude_deg, longitude_deg, timezone_hrs);
        } catch (IOError e) {
            printerr ("Location detection failed: %s\n", e.message);
            // If timezone is not specified by CLI, use system timezone as default
            if (timezone_hrs.is_nan ()) {
                var timezone = new TimeZone.local ();
                var time_interval = timezone.find_interval (GLib.TimeType.UNIVERSAL, new DateTime.now_utc().to_unix ());
                timezone_hrs = timezone.get_offset (time_interval) / 3600.0;
                printerr ("Using system timezone: UTC%+.2f\n", timezone_hrs);
            }
            // Location (latitude/longitude) must be specified manually
            if (latitude_deg.is_nan () || longitude_deg.is_nan ()) {
                printerr ("Please specify location manually using --latitude and --longitude.\n");
                return 1;
            }
        }
    }

    DateTime date_obj;
    if (date_str == null) {
        date_obj = new DateTime.now_local ();
    } else {
        // Complete date string to ISO 8601 format if needed
        string iso_str;
        int pos_T = date_str.index_of_char ('T');
        if (pos_T > 0) {
            iso_str = date_str;
            string tz_part = date_str[pos_T:];
            if (tz_part.index_of_char ('Z') < 0 && tz_part.index_of_char ('+') < 0 && tz_part.index_of_char ('-') < 0) {
                iso_str += "Z"; // Append 'Z' for UTC if no timezone is specified
            }
        } else {
            pos_T = date_str.length;
            iso_str = date_str + "T12:00:00Z";
        }

        date_obj = new DateTime.from_iso8601 (iso_str, null);
        if (date_obj == null) {
            printerr ("Invalid date format: %s\n", date_str);
            return 1;
        }
    }

    var date = Date ();
    date.set_dmy ((DateDay) date_obj.get_day_of_month (), date_obj.get_month (), (DateYear) date_obj.get_year ());
    var julian_date = date.get_julian ();

    double day_length, sunrise_time, sunset_time;
    calculate_day_length (
        latitude_deg * DEG2RAD, longitude_deg, timezone_hrs,
        (double) julian_date, horizon_deg,
        out day_length, out sunrise_time, out sunset_time
    );

    print ("--- Day Length Calculation Results ---\n");
    print ("Date:\t\t%s\n", date_obj.format ("%Y-%m-%d"));
    print ("Latitude:\t%.2f°\n", latitude_deg);
    print ("Longitude:\t%.2f°\n", longitude_deg);
    print ("Timezone:\tUTC%+.2f\n", timezone_hrs);
    print ("Horizon Angle:\t%.2f°\n", horizon_deg);
    print ("--------------------------------------\n");
    print ("Day Length:\t%.2f hours (%s)\n", day_length, format_time(day_length));
    print ("Sunrise:\t%s\n", format_time(sunrise_time));
    print ("Sunset:\t\t%s\n", format_time(sunset_time));
    print ("--------------------------------------\n");

    return 0;
}
