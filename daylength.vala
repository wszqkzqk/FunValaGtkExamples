#!/usr/bin/env -S vala -X -lm -X -O2 -X -march=native -X -pipe
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
 * Calculates day length using high-precision astronomical formula.
 * Based on http://www.jgiesen.de/elevaz/basics/meeus.htm
 * 
 * @param latitude_rad Latitude in radians.
 * @param julian_date GLib's Julian Date for the day (from 0001-01-01).
 * @param horizon_angle_deg Horizon angle correction in degrees (default -0.83° for atmospheric refraction).
 * @return Day length in hours.
 */
private double calculate_day_length (double latitude_rad, double julian_date, double horizon_angle_deg = -0.83) {
    double sin_lat = Math.sin (latitude_rad);
    double cos_lat = Math.cos (latitude_rad);
    // Base days from J2000.0 epoch (GLib's Julian Date is days since 0001-01-01 12:00 UTC)
    double base_days_from_epoch = julian_date - 730120.5; // julian_date's 00:00 UTC to 2000-01-01 12:00 UTC
    // Pre-compute obliquity with higher-order terms (changes very slowly)
    double base_days_sq = base_days_from_epoch * base_days_from_epoch;
    double base_days_cb = base_days_sq * base_days_from_epoch;
    double obliquity_deg = 23.439291111 - 3.560347e-7 * base_days_from_epoch - 1.2285e-16 * base_days_sq + 1.0335e-20 * base_days_cb;
    double obliquity_sin = Math.sin (obliquity_deg * DEG2RAD);
    // Mean anomaly of the sun (degrees) with higher-order terms
    double days_from_epoch_sq = base_days_from_epoch * base_days_from_epoch;
    double days_from_epoch_cb = days_from_epoch_sq * base_days_from_epoch;
    double mean_anomaly_deg = 357.52910 + 0.985600282 * base_days_from_epoch - 1.1686e-13 * days_from_epoch_sq - 9.85e-21 * days_from_epoch_cb;
    mean_anomaly_deg = Math.fmod (mean_anomaly_deg, 360.0);
    if (mean_anomaly_deg < 0) {
        mean_anomaly_deg += 360.0;
    }
    // Mean longitude of the sun (degrees) with higher-order terms
    double mean_longitude_deg = 280.46645 + 0.98564736 * base_days_from_epoch + 2.2727e-13 * days_from_epoch_sq;
    mean_longitude_deg = Math.fmod (mean_longitude_deg, 360.0);
    if (mean_longitude_deg < 0) {
        mean_longitude_deg += 360.0;
    }
    // Ecliptic longitude corrections
    double ecliptic_c1 = 1.914600 - 1.3188e-7 * base_days_from_epoch - 1.049e-14 * base_days_sq;
    double ecliptic_c2 = 0.019993 - 2.7652e-9 * base_days_from_epoch;
    double ecliptic_c3 = 0.000290;
    // Ecliptic longitude of the sun (degrees) with higher-order corrections
    double mean_anomaly_rad = mean_anomaly_deg * DEG2RAD;
    double ecliptic_longitude_deg = mean_longitude_deg + ecliptic_c1 * Math.sin (mean_anomaly_rad) + ecliptic_c2 * Math.sin (2.0 * mean_anomaly_rad) + ecliptic_c3 * Math.sin (3.0 * mean_anomaly_rad);
    ecliptic_longitude_deg = Math.fmod (ecliptic_longitude_deg, 360.0);
    if (ecliptic_longitude_deg < 0) {
        ecliptic_longitude_deg += 360.0;
    }
    // Solar declination (radians)
    double ecliptic_longitude_rad = ecliptic_longitude_deg * DEG2RAD;
    double ecliptic_longitude_sin = Math.sin (ecliptic_longitude_rad);
    double declination_sin = (obliquity_sin * ecliptic_longitude_sin).clamp (-1.0, 1.0);
    double declination_rad = Math.asin (declination_sin.clamp (-1.0, 1.0));
    // Convert horizon angle to radians
    double horizon_angle_rad = horizon_angle_deg * DEG2RAD; 
    // Calculate hour angle at sunrise/sunset with horizon correction
    double cos_hour_angle = (Math.sin (horizon_angle_rad) - sin_lat * declination_sin) 
        / (cos_lat * Math.cos (declination_rad));
    if (cos_hour_angle.is_nan ()) {
        // Invalid value, return 12.0 hours
        return 12.0;
    } else if (cos_hour_angle >= 1.0) {
        // Polar night (sun never rises)
        return 0.0;
    } else if (cos_hour_angle <= -1.0) {
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
 * Main entry point.
 * @param args Command line arguments.
 * @return Exit status code.
 */
public static int main (string[] args) {
    Intl.setlocale ();
    // Define and parse command line arguments
    double latitude_deg = 0.0; 
    string? date_str = null;
    double horizon_deg = -0.83;
    OptionEntry[] entries = {
        { "latitude", 'l', OptionFlags.NONE, OptionArg.DOUBLE, out latitude_deg,
          "Geographic latitude of observation point (in degrees, positive for North, negative for South, default: 0.0).", "DEG" },
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
    var date = Date ();
    date.set_dmy ((DateDay) date_obj.get_day_of_month (), date_obj.get_month (), (DateYear) date_obj.get_year ());
    var julian_date = date.get_julian ();

    double latitude_rad = DEG2RAD * latitude_deg;
    double day_length = calculate_day_length (latitude_rad, julian_date, horizon_deg);
    print (
        "%s  |  Latitude: %.2f deg  |  Horizon: %.2f deg  |  Daylight: %.2f hours\n",
        date_obj.format ("%Y-%m-%d"),
        latitude_deg,
        horizon_deg,
        day_length
    );
    return 0;
}
