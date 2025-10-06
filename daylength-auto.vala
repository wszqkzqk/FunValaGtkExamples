#!/usr/bin/env -S vala --pkg=gio-2.0 --pkg=json-glib-1.0 -X -lm -X -O2 -X -march=native -X -pipe
/* SPDX-License-Identifier: LGPL-2.1-or-later */

/**
 * Day Length Calculator CLI with Auto-Detection and Horizon Correction.
 * Copyright (C) 2025 wszqkzqk <wszqkzqk@qq.com>
 * 
 * A command-line tool that calculates day length using astronomical formulas
 * based on solar declination, with optional auto-location detection.
 */
private const double DEG2RAD = Math.PI / 180.0;
private const double RAD2DEG = 180.0 / Math.PI;

/**
 * Returns the number of days in a given year.
 */
private inline int days_in_year (int year) {
    if ((year % 4 == 0) && ((year % 100 != 0) || (year % 400 == 0))) {
        return 366;
    }
    return 365;
}

/**
 * Calculates day length using simplified astronomical formula.
 * 
 * This method uses the solar declination angle and hour angle formula
 * to directly calculate day length without iteration.
 * 
 * @param latitude_rad Latitude in radians.
 * @param day_of_year Day of the year (1-365/366).
 * @param year The year.
 * @param horizon_angle_deg Horizon angle correction in degrees (default -0.83° for atmospheric refraction).
 * @return Day length in hours.
 */
private double calculate_day_length_simplified (double latitude_rad, int day_of_year, int year, double horizon_angle_deg = -0.83) {
    double days_in_year_val = days_in_year (year);
    
    // Calculate fractional year in radians
    double gamma_rad = (2.0 * Math.PI / days_in_year_val) * day_of_year;
    
    // Solar declination using NOAA formula (radians)
    double decl_rad = 0.006918
        - 0.399912 * Math.cos (gamma_rad)
        + 0.070257 * Math.sin (gamma_rad)
        - 0.006758 * Math.cos (2.0 * gamma_rad)
        + 0.000907 * Math.sin (2.0 * gamma_rad)
        - 0.002697 * Math.cos (3.0 * gamma_rad)
        + 0.001480 * Math.sin (3.0 * gamma_rad);
    
    // Convert horizon angle to radians
    double horizon_angle_rad = horizon_angle_deg * DEG2RAD;
    
    // Calculate hour angle at sunrise/sunset with horizon correction
    // cos(hour_angle) = (sin(horizon_angle) - sin(latitude) * sin(declination)) / (cos(latitude) * cos(declination))
    double cos_hour_angle = (Math.sin (horizon_angle_rad) - Math.sin (latitude_rad) * Math.sin (decl_rad)) 
                          / (Math.cos (latitude_rad) * Math.cos (decl_rad));

    if (cos_hour_angle.is_nan ()) {
        // Invalid value, return 12.0 hours
        return 12.0;
    } else if (cos_hour_angle > 1.0) {
        // Polar night (sun never rises)
        return 0.0;
    } else if (cos_hour_angle < -1.0) {
        // Polar day (sun never sets)
        return 24.0;
    }

    // Hour angle in radians
    double hour_angle_rad = Math.acos (cos_hour_angle);
    
    // Day length in hours (hour angle is in radians, convert to hours)
    // Sunrise to sunset is 2 * hour_angle, and there are 24 hours / (2*π radians)
    return (2.0 * hour_angle_rad * 24.0) / (2.0 * Math.PI);
}

/**
 * Asynchronously gets current location using IP geolocation service.
 */
private async double get_location_async () throws IOError {
    var file = File.new_for_uri ("https://ipapi.co/json/");
    var parser = new Json.Parser ();
    double latitude = 0.0;

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

    if (root_object.has_member ("latitude")) {
        latitude = root_object.get_double_member ("latitude");
    } else {
        throw new IOError.FAILED ("No latitude found in the response");
    }
    return latitude;
}

/**
 * Main entry point.
 * @param args Command line arguments.
 * @return Exit status code.
 */
public static async int main (string[] args) {
    Intl.setlocale ();
    // Define and parse command line arguments
    double latitude_deg = double.NAN; 
    string? date_str = null;
    double horizon_deg = -0.83;
    OptionEntry[] entries = {
        { "latitude", 'l', OptionFlags.NONE, OptionArg.DOUBLE, out latitude_deg,
          "Geographic latitude of observation point (in degrees, positive for North, negative for South). If not specified, auto-detects via IP.", "DEG" },
        { "date", 'd', OptionFlags.NONE, OptionArg.STRING, out date_str,
          "Date (format: YYYY-MM-DD), defaults to today", "DATE" },
        { "horizon", '\0', OptionFlags.NONE, OptionArg.DOUBLE, out horizon_deg,
          "Horizon angle correction in degrees (default: -0.83 for atmospheric refraction)", "DEG" },
        null
    };

    OptionContext context = new OptionContext();
    context.set_help_enabled (true);
    context.set_summary ("Calculate daylight duration (in hours) for given date and latitude\n");
    context.add_main_entries (entries, null);

    try {
        context.parse (ref args);
    } catch (Error e) {
        printerr ("Error parsing arguments: %s\n", e.message);
        return 1;
    }

    // Use current date if not provided
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

    // Auto-detect latitude if not provided
    if (latitude_deg.is_nan ()) {
        try {
            printerr ("Detecting location...\n");
            latitude_deg = yield get_location_async ();
            printerr ("Detected latitude: %.2f°\n", latitude_deg);
        } catch (IOError e) {
            printerr ("Location detection failed: %s\n", e.message);
            return 1;
        }
    }

    double latitude_rad = DEG2RAD * latitude_deg;
    int year = date_obj.get_year ();
    int day_of_year = date_obj.get_day_of_year ();
    double day_length = calculate_day_length_simplified (latitude_rad, day_of_year, year, horizon_deg);
    print (
        "%s  |  Latitude: %.2f deg  |  Horizon: %.2f deg  |  Daylight: %.2f hours\n",
        date_obj.format ("%Y-%m-%d"),
        latitude_deg,
        horizon_deg,
        day_length
    );
    return 0;
}
