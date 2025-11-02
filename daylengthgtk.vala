#!/usr/bin/env -S vala --pkg=gtk4 --pkg=json-glib-1.0 -X -lm -X -O2 -X -march=native -X -pipe
/* SPDX-License-Identifier: LGPL-2.1-or-later */

/**
 * Day Length Calculator Application.
 * Copyright (C) 2025 wszqkzqk <wszqkzqk@qq.com>
 * 
 * A GTK4 application that calculates and visualizes day length
 * throughout the year using astronomical formulas based on solar declination.
 */
public class DayLengthApp : Gtk.Application {
    // Constants
    private const double DEG2RAD = Math.PI / 180.0;
    private const double RAD2DEG = 180.0 / Math.PI;
    private const int MARGIN_LEFT = 70;
    private const int MARGIN_RIGHT = 20;
    private const int MARGIN_TOP = 50;
    private const int MARGIN_BOTTOM = 70;

    // Model / persistent state
    private double latitude = 0.0;
    private double longitude = 0.0;
    private double timezone_offset_hours = 0.0;
    private int selected_year;
    private double horizon_angle = -0.83; // Refraction-corrected horizon angle in degrees
    private double[] day_lengths; // Hours of daylight for each day
    private double[] sunrise_times;
    private double[] sunset_times; // Sunset times for each day
    private int clicked_day = -1; // Selected day on chart
    private bool has_click_point = false;

    // UI widgets
    private Gtk.ApplicationWindow window;
    private Gtk.DrawingArea drawing_area;
    private Gtk.Label click_info_label;
    private Gtk.Stack location_stack;
    private Gtk.Spinner location_spinner;
    private Gtk.Button location_button;
    private Gtk.SpinButton latitude_spin;
    private Gtk.SpinButton longitude_spin;
    private Gtk.SpinButton timezone_spin;
    private Gtk.SpinButton year_spin;
    private Gtk.SpinButton horizon_spin;

    /**
     * Creates a new DayLengthApp instance.
     */
    public DayLengthApp () {
        Object (application_id: "com.github.wszqkzqk.DayLengthGtk");
        DateTime now = new DateTime.now_local ();
        selected_year = now.get_year ();
    }

    protected override void activate () {
        window = new Gtk.ApplicationWindow (this) {
            title = "Day Length Calculator",
            default_width = 1000,
            default_height = 700,
        };

        var main_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);

        var left_panel = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
            hexpand = false,
            vexpand = true,
            width_request = 320,
            margin_start = 12,
            margin_end = 12,
            margin_top = 12,
            margin_bottom = 12,
        };

        // Location Settings Group
        var location_group = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        var location_label = new Gtk.Label ("<b>Location Settings</b>") {
            use_markup = true,
            halign = Gtk.Align.START,
        };
        location_group.append (location_label);

        // Auto-detect location
        var location_detect_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        location_stack = new Gtk.Stack () {
            hhomogeneous = true,
            vhomogeneous = true,
            transition_type = Gtk.StackTransitionType.CROSSFADE,
        };
        location_spinner = new Gtk.Spinner ();
        location_button = new Gtk.Button.with_label ("Detect Location") {
            valign = Gtk.Align.CENTER,
            tooltip_text = "Auto-detect current location",
            hexpand = true,
        };
        location_button.clicked.connect (on_auto_detect_location);
        location_stack.add_child (location_button);
        location_stack.add_child (location_spinner);
        location_stack.visible_child = location_button;
        location_detect_box.append (location_stack);
        location_group.append (location_detect_box);

        var settings_grid = new Gtk.Grid () {
            column_spacing = 10,
            row_spacing = 8,
            margin_top = 5,
        };

        var latitude_label = new Gtk.Label ("Latitude:") {
            halign = Gtk.Align.START,
        };
        latitude_spin = new Gtk.SpinButton.with_range (-90.0, 90.0, 0.1) {
            value = latitude,
            digits = 2,
        };
        latitude_spin.value_changed.connect (() => {
            latitude = latitude_spin.value;
            update_plot_data ();
            drawing_area.queue_draw ();
        });

        var longitude_label = new Gtk.Label ("Longitude:") {
            halign = Gtk.Align.START,
        };
        longitude_spin = new Gtk.SpinButton.with_range (-180, 180, 0.1) {
            value = longitude,
            digits = 2,
        };
        longitude_spin.value_changed.connect (() => {
            longitude = longitude_spin.value;
            update_plot_data ();
            drawing_area.queue_draw ();
        });

        var timezone_label = new Gtk.Label ("Timezone:") {
            halign = Gtk.Align.START,
        };
        timezone_spin = new Gtk.SpinButton.with_range (-12, 14, 0.5) {
            value = timezone_offset_hours,
            digits = 2,
        };
        timezone_spin.value_changed.connect (() => {
            timezone_offset_hours = timezone_spin.value;
            update_plot_data ();
            drawing_area.queue_draw ();
        });

        var horizon_label = new Gtk.Label ("Horizon Angle:") {
            halign = Gtk.Align.START,
        };
        horizon_spin = new Gtk.SpinButton.with_range (-20.0, 20.0, 0.01) {
            value = horizon_angle,
            digits = 2,
        };
        horizon_spin.value_changed.connect (() => {
            horizon_angle = horizon_spin.value;
            update_plot_data ();
            drawing_area.queue_draw ();
        });

        settings_grid.attach (latitude_label, 0, 0, 1, 1);
        settings_grid.attach (latitude_spin, 1, 0, 1, 1);
        settings_grid.attach (longitude_label, 0, 1, 1, 1);
        settings_grid.attach (longitude_spin, 1, 1, 1, 1);
        settings_grid.attach (timezone_label, 0, 2, 1, 1);
        settings_grid.attach (timezone_spin, 1, 2, 1, 1);
        settings_grid.attach (horizon_label, 0, 3, 1, 1);
        settings_grid.attach (horizon_spin, 1, 3, 1, 1);

        location_group.append (settings_grid);
        left_panel.append (location_group);

        // Year Selection Group
        var year_group = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        var year_label = new Gtk.Label ("<b>Year Selection</b>") {
            use_markup = true,
            halign = Gtk.Align.START,
        };
        year_spin = new Gtk.SpinButton.with_range (1, 9999, 1) {
            value = selected_year,
            digits = 0,
        };
        year_spin.value_changed.connect (() => {
            selected_year = (int) year_spin.value;
            update_plot_data ();
            drawing_area.queue_draw ();
        });
        year_group.append (year_label);
        year_group.append (year_spin);
        left_panel.append (year_group);

        // Export Group
        var export_group = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        var export_label = new Gtk.Label ("<b>Export</b>") {
            use_markup = true,
            halign = Gtk.Align.START,
        };

        var export_buttons_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 5) {
            homogeneous = true,
        };

        var export_image_button = new Gtk.Button.with_label ("Export Image");
        export_image_button.clicked.connect (on_export_image_clicked);

        var export_csv_button = new Gtk.Button.with_label ("Export CSV");
        export_csv_button.clicked.connect (on_export_csv_clicked);

        export_buttons_box.append (export_image_button);
        export_buttons_box.append (export_csv_button);

        export_group.append (export_label);
        export_group.append (export_buttons_box);
        left_panel.append (export_group);

        // Click Info Group
        var click_info_group = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        var click_info_title = new Gtk.Label ("<b>Selected Day</b>") {
            use_markup = true,
            halign = Gtk.Align.START,
        };
        click_info_label = new Gtk.Label ("Click on chart to view data\n") {
            halign = Gtk.Align.START,
            margin_start = 12,
            margin_end = 12,
            margin_top = 6,
            margin_bottom = 6,
            wrap = true,
        };
        click_info_group.append (click_info_title);
        click_info_group.append (click_info_label);
        left_panel.append (click_info_group);

        drawing_area = new Gtk.DrawingArea () {
            hexpand = true,
            vexpand = true,
            width_request = 600,
            height_request = 500,
        };
        drawing_area.set_draw_func (draw_day_length_chart);

        // Add click event controller
        var click_controller = new Gtk.GestureClick ();
        click_controller.pressed.connect (on_chart_clicked);
        drawing_area.add_controller (click_controller);

        main_box.append (left_panel);
        main_box.append (drawing_area);

        update_plot_data ();

        window.child = main_box;
        window.present ();
    }

    /**
     * Returns the number of days in a given year.
     *
     * @param year The year to query.
     * @return The number of days in the year (365 or 366).
     */
    private inline int days_in_year (int year) {
        if ((year % 4 == 0) && ((year % 100 != 0) || (year % 400 == 0))) {
            return 366;
        }
        return 365;
    }

    /**
     * Computes solar parameters: declination and equation of time.
     *
     * @param base_days_from_epoch Days from the chosen epoch (e.g. days since J2000-like reference) at UTC midnight.
     * @param time_local_hours Local time in hours for which to compute the parameters (e.g. 12.0 for noon).
     * @param obliquity_sin Sine of the Earth's obliquity (precomputed).
     * @param obliquity_cos Cosine of the Earth's obliquity (precomputed).
     * @param ecliptic_c1 First-order ecliptic correction coefficient.
     * @param ecliptic_c2 Second-order ecliptic correction coefficient.
     * @param out_declination_sin (out) Receives sine of the solar declination.
     * @param out_declination_cos (out) Receives cosine of the solar declination.
     * @param out_eqtime_minutes (out) Receives the equation of time in minutes.
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

        double mean_anomaly_deg = 357.52910 + 0.985600282 * days_from_epoch - 1.1686e-13 * days_sq - 9.85e-21 * days_cb;
        double mean_anomaly_rad = mean_anomaly_deg * DEG2RAD;

        double mean_longitude_deg = Math.fmod (280.46645 + 0.98564736 * days_from_epoch + 2.2727e-13 * days_sq, 360.0);
        if (mean_longitude_deg < 0) {
            mean_longitude_deg += 360.0;
        }

        double ecliptic_longitude_deg = mean_longitude_deg
            + ecliptic_c1 * Math.sin (mean_anomaly_rad)
            + ecliptic_c2 * Math.sin (2.0 * mean_anomaly_rad)
            + 0.000290 * Math.sin (3.0 * mean_anomaly_rad);

        double ecliptic_longitude_rad = ecliptic_longitude_deg * DEG2RAD;
        double ecliptic_longitude_sin = Math.sin (ecliptic_longitude_rad);
        double ecliptic_longitude_cos = Math.cos (ecliptic_longitude_rad);

        out_declination_sin = (obliquity_sin * ecliptic_longitude_sin).clamp (-1.0, 1.0);
        out_declination_cos = Math.sqrt (1.0 - out_declination_sin * out_declination_sin);

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
     * Calculates day length using high-precision astronomical formula.
     * 
     * @param latitude_rad Latitude in radians.
     * @param longitude_deg Longitude in degrees.
     * @param timezone_offset_hrs Timezone offset in hours.
     * @param julian_date GLib's Julian Date for the day (from 0001-01-01).
     * @param horizon_angle_deg Horizon angle correction in degrees (default -0.83° for atmospheric refraction).
     * @return Day length in hours.
     */
    private void calculate_day_length (
        double latitude_rad, double longitude_deg, double timezone_offset_hrs, double julian_date, double horizon_angle_deg,
        out double day_length, out double sunrise_time, out double sunset_time
    ) {
        double sin_lat = Math.sin (latitude_rad);
        double cos_lat = Math.cos (latitude_rad);
        double sin_horizon = Math.sin (horizon_angle_deg * DEG2RAD);

        double base_days_from_epoch_utc_midnight = (julian_date - 730120.5) - timezone_offset_hrs / 24.0;
        double base_days_sq = base_days_from_epoch_utc_midnight * base_days_from_epoch_utc_midnight;
        double base_days_cb = base_days_sq * base_days_from_epoch_utc_midnight;
        double obliquity_deg = 23.439291111 - 3.560347e-7 * base_days_from_epoch_utc_midnight - 1.2285e-16 * base_days_sq + 1.0335e-20 * base_days_cb;
        double obliquity_sin = Math.sin (obliquity_deg * DEG2RAD);
        double obliquity_cos = Math.cos (obliquity_deg * DEG2RAD);

        double ecliptic_c1 = 1.914600 - 1.3188e-7 * base_days_from_epoch_utc_midnight - 1.049e-14 * base_days_sq;
        double ecliptic_c2 = 0.019993 - 2.7652e-9 * base_days_from_epoch_utc_midnight;

        double tst_offset = 4.0 * longitude_deg - 60.0 * timezone_offset_hrs;

        double declination_sin, declination_cos, eqtime_minutes;
        compute_solar_parameters (
            base_days_from_epoch_utc_midnight, 12.0,
            obliquity_sin, obliquity_cos, ecliptic_c1, ecliptic_c2,
            out declination_sin, out declination_cos, out eqtime_minutes
        );

        double cos_ha = (Math.sin (horizon_angle_deg * DEG2RAD) - sin_lat * declination_sin) / (cos_lat * declination_cos);

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
     * Updates plot data for all days in the selected year.
     */
    private void update_plot_data () {
        int total_days = days_in_year (selected_year);
        day_lengths = new double[total_days];
        sunrise_times = new double[total_days];
        sunset_times = new double[total_days];

        double latitude_rad = latitude * DEG2RAD;

        // Get Julian Date for January 1st of the selected year
        var date = Date ();
        date.set_dmy (1, 1, (DateYear) selected_year);
        uint base_julian_date = date.get_julian ();

        for (int day = 0; day < total_days; day += 1) {
            calculate_day_length (
                latitude_rad, longitude, timezone_offset_hours, (double) (base_julian_date + day), horizon_angle,
                out day_lengths[day], out sunrise_times[day], out sunset_times[day]
            );
        }

        // Clear click point when data updates
        has_click_point = false;
        click_info_label.label = "Click on chart to view data\n\n";
    }

    /**
     * Handles auto-detect location button click.
     */
    private void on_auto_detect_location () {
        location_button.sensitive = false;
        location_stack.visible_child = location_spinner;
        location_spinner.start ();

        get_location_async.begin ((obj, res) => {
            try {
                get_location_async.end (res);
            } catch (Error e) {
                show_error_dialog ("Location Detection Failed", e.message);
            }

            location_button.sensitive = true;
            location_spinner.stop ();
            location_stack.visible_child = location_button;
        });
    }

    /**
     * Asynchronously gets current location using IP geolocation service.
     */
    private async void get_location_async () throws IOError {
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

        if (root_object.has_member ("latitude")) {
            latitude = root_object.get_double_member ("latitude");
        } else {
            throw new IOError.FAILED ("No latitude found in the response");
        }
        if (root_object.has_member ("longitude")) {
            longitude = root_object.get_double_member ("longitude");
        } else {
            throw new IOError.FAILED ("No longitude found in the response");
        }

        double network_tz_offset = 0.0;
        bool has_network_tz = false;

        if (root_object.has_member ("utc_offset")) {
            var offset_str = root_object.get_string_member ("utc_offset");
            network_tz_offset = double.parse (offset_str) / 100.0;
            has_network_tz = true;
        }

        var timezone = new TimeZone.local ();
        var interval = timezone.find_interval (GLib.TimeType.UNIVERSAL, new DateTime.now_utc ().to_unix ());
        double local_tz_offset = timezone.get_offset (interval) / 3600.0;

        const double TZ_EPSILON = 0.01; // Epsilon for floating point comparison
        if (has_network_tz && (!(-TZ_EPSILON < (network_tz_offset - local_tz_offset) < TZ_EPSILON))) {
            var dialog = new Gtk.AlertDialog (
                "Timezone Mismatch: The timezone from the network (UTC%+.2f) differs from your system's timezone (UTC%+.2f).\n\nWhich one would you like to use?",
                network_tz_offset,
                local_tz_offset
            );
            dialog.set_buttons ({"Use Network Timezone", "Use System Timezone"});
            dialog.set_default_button (0); // Default to network timezone

            try {
                var choice = yield dialog.choose (window, null);
                timezone_offset_hours = (choice == 0) ? network_tz_offset : local_tz_offset;
            } catch (Error e) {
                throw new IOError.FAILED ("Failed to get user choice: %s", e.message);
            }
        } else {
            timezone_offset_hours = local_tz_offset;
        }

        latitude_spin.value = latitude;
        longitude_spin.value = longitude;
        timezone_spin.value = timezone_offset_hours;
        update_plot_data ();
        drawing_area.queue_draw ();
    }

    /**
     * Shows an error dialog.
     */
    private void show_error_dialog (string title, string error_message) {
        var dialog = new Gtk.AlertDialog (
            "%s: %s",
            title,
            error_message
        );
        dialog.show (window);
        message ("%s: %s", title, error_message);
    }

    /**
     * Handles mouse click events on the chart.
     *
     * @param n_press Number of presses (1 for single click).
     * @param x X coordinate of the click within the drawing area.
     * @param y Y coordinate of the click within the drawing area.
     */
    private void on_chart_clicked (int n_press, double x, double y) {
        int width = drawing_area.get_width ();
        int height = drawing_area.get_height ();
        int chart_width = width - MARGIN_LEFT - MARGIN_RIGHT;
        int total_days = day_lengths.length;

        if (x >= MARGIN_LEFT && x <= width - MARGIN_RIGHT && 
            y >= MARGIN_TOP && y <= height - MARGIN_BOTTOM && n_press == 1) {
            
            double fraction = (x - MARGIN_LEFT) / chart_width;
            clicked_day = (int) (fraction * (total_days - 1));
            clicked_day = clicked_day.clamp (0, total_days - 1);
            has_click_point = true;

            // Get date for this day
            var date = new DateTime (new TimeZone.local (), selected_year, 1, 1, 0, 0, 0).add_days (clicked_day);
            
            string sunrise_str, sunset_str;
            if (sunrise_times[clicked_day].is_nan () || sunset_times[clicked_day].is_nan ()) {
                sunrise_str = "-";
                sunset_str = "-";
            } else {
                int sunrise_h = (int) sunrise_times[clicked_day];
                int sunrise_m = (int) ((sunrise_times[clicked_day] - sunrise_h) * 60);
                sunrise_str = "%02d:%02d".printf (sunrise_h, sunrise_m);

                int sunset_h = (int) sunset_times[clicked_day];
                int sunset_m = (int) ((sunset_times[clicked_day] - sunset_h) * 60);
                sunset_str = "%02d:%02d".printf (sunset_h, sunset_m);
            }

            string info_text = "Date: %s (Day %d)\nDay Length: %.2f hours\nSunrise: %s, Sunset: %s".printf (
                date.format ("%B %d"), clicked_day + 1, day_lengths[clicked_day], sunrise_str, sunset_str
            );

            click_info_label.label = info_text;
            drawing_area.queue_draw ();
        } else {
            has_click_point = false;
            click_info_label.label = "Click on chart to view data\n";
            drawing_area.queue_draw ();
        }
    }

    /**
     * Draws the day length chart.
     *
     * @param area The Gtk.DrawingArea being drawn into.
     * @param cr The Cairo context used for drawing.
     * @param width Width of the drawing area in pixels.
     * @param height Height of the drawing area in pixels.
     */
    private void draw_day_length_chart (Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
        // Light theme colors
        double bg_r = 1.0, bg_g = 1.0, bg_b = 1.0;
        double grid_r = 0.5, grid_g = 0.5, grid_b = 0.5, grid_a = 0.5;
        double axis_r = 0.0, axis_g = 0.0, axis_b = 0.0;
        double text_r = 0.0, text_g = 0.0, text_b = 0.0;
        double curve_r = 1.0, curve_g = 0.5, curve_b = 0.0;
        double point_r = 0.0, point_g = 0.0, point_b = 1.0;
        double line_r = 0.0, line_g = 0.0, line_b = 1.0, line_a = 0.5;

        // Fill background
        cr.set_source_rgb (bg_r, bg_g, bg_b);
        cr.paint ();

        int chart_width = width - MARGIN_LEFT - MARGIN_RIGHT;
        int chart_height = height - MARGIN_TOP - MARGIN_BOTTOM;
        int total_days = day_lengths.length;

        double y_min = -0.5, y_max = 24.5;

        // Draw grid lines
        cr.set_source_rgba (grid_r, grid_g, grid_b, grid_a);
        cr.set_line_width (1.0);
        
        // Horizontal grid (every 3 hours)
        for (int tick = 0; tick <= 24; tick += 3) {
            double y_val = MARGIN_TOP + (chart_height * (1 - (tick - y_min) / (y_max - y_min)));
            cr.move_to (MARGIN_LEFT, y_val);
            cr.line_to (width - MARGIN_RIGHT, y_val);
            cr.stroke ();
        }
        
        // Vertical grid (start of each month)
        for (int month = 1; month <= 12; month += 1) {
            var month_start = new DateTime (new TimeZone.local (), selected_year, month, 1, 0, 0, 0);
            int day_num = month_start.get_day_of_year ();
            double x_pos = MARGIN_LEFT + (chart_width * ((double) (day_num - 1) / (total_days - 1)));
            cr.move_to (x_pos, MARGIN_TOP);
            cr.line_to (x_pos, height - MARGIN_BOTTOM);
            cr.stroke ();
        }

        // Draw axes
        cr.set_source_rgb (axis_r, axis_g, axis_b);
        cr.set_line_width (2.0);
        cr.move_to (MARGIN_LEFT, height - MARGIN_BOTTOM);
        cr.line_to (width - MARGIN_RIGHT, height - MARGIN_BOTTOM);
        cr.stroke ();
        cr.move_to (MARGIN_LEFT, MARGIN_TOP);
        cr.line_to (MARGIN_LEFT, height - MARGIN_BOTTOM);
        cr.stroke ();

        // Draw Y axis ticks and labels
        cr.set_source_rgb (text_r, text_g, text_b);
        cr.set_line_width (1.0);
        cr.set_font_size (20);
        for (int tick = 0; tick <= 24; tick += 3) {
            double y_val = MARGIN_TOP + (chart_height * (1 - (tick - y_min) / (y_max - y_min)));
            cr.move_to (MARGIN_LEFT - 5, y_val);
            cr.line_to (MARGIN_LEFT, y_val);
            cr.stroke ();
            
            var te = Cairo.TextExtents ();
            var txt = tick.to_string ();
            cr.text_extents (txt, out te);
            cr.move_to (MARGIN_LEFT - 10 - te.width, y_val + te.height / 2);
            cr.show_text (txt);
        }

        // Draw X axis ticks and labels (months)
        for (int month = 1; month <= 12; month += 1) {
            var month_start = new DateTime (new TimeZone.local (), selected_year, month, 1, 0, 0, 0);
            int day_num = month_start.get_day_of_year ();
            double x_pos = MARGIN_LEFT + (chart_width * ((double) (day_num - 1) / (total_days - 1)));
            cr.move_to (x_pos, height - MARGIN_BOTTOM);
            cr.line_to (x_pos, height - MARGIN_BOTTOM + 5);
            cr.stroke ();
            
            string label = month.to_string ();
            var te = Cairo.TextExtents ();
            cr.text_extents (label, out te);
            cr.move_to (x_pos - te.width / 2, height - MARGIN_BOTTOM + 25);
            cr.show_text (label);
        }

        // Draw axis titles
        string x_title = "Date (Month)";
        var x_te = Cairo.TextExtents ();
        cr.text_extents (x_title, out x_te);
        cr.move_to ((double) width / 2 - x_te.width / 2, height - MARGIN_BOTTOM + 50);
        cr.show_text (x_title);

        string y_title = "Day Length (hours)";
        var y_te = Cairo.TextExtents ();
        cr.text_extents (y_title, out y_te);
        cr.save ();
        cr.translate (MARGIN_LEFT - 45, (double) height / 2);
        cr.rotate (-Math.PI / 2);
        cr.move_to (-y_te.width / 2, 0);
        cr.show_text (y_title);
        cr.restore ();

        // Draw caption
        string caption = "Lat: %.2f°, Lon: %.2f°, TZ: UTC%+.2f, Year: %d, Horizon: %.2f°".printf (
            latitude, longitude, timezone_offset_hours, selected_year, horizon_angle
        );
        cr.set_font_size (18);
        var cap_te = Cairo.TextExtents ();
        cr.text_extents (caption, out cap_te);
        cr.move_to ((width - cap_te.width) / 2, (double) MARGIN_TOP / 2);
        cr.show_text (caption);

        // Draw data curve
        cr.set_source_rgb (curve_r, curve_g, curve_b);
        cr.set_line_width (2.5);
        for (int i = 0; i < total_days; i += 1) {
            double x = MARGIN_LEFT + (chart_width * ((double) i / (total_days - 1)));
            double y = MARGIN_TOP + (chart_height * (1 - (day_lengths[i] - y_min) / (y_max - y_min)));
            if (i == 0) {
                cr.move_to (x, y);
            } else {
                cr.line_to (x, y);
            }
        }
        cr.stroke ();

        // Draw clicked point if exists
        if (has_click_point && clicked_day >= 0 && clicked_day < total_days) {
            double x = MARGIN_LEFT + (chart_width * ((double) clicked_day / (total_days - 1)));
            double y = MARGIN_TOP + (chart_height * (1 - (day_lengths[clicked_day] - y_min) / (y_max - y_min)));

            // Draw vertical guide line
            cr.set_source_rgba (line_r, line_g, line_b, line_a);
            cr.set_line_width (1.5);
            cr.move_to (x, MARGIN_TOP);
            cr.line_to (x, height - MARGIN_BOTTOM);
            cr.stroke ();

            // Draw horizontal guide line
            cr.move_to (MARGIN_LEFT, y);
            cr.line_to (width - MARGIN_RIGHT, y);
            cr.stroke ();

            // Draw point
            cr.set_source_rgb (point_r, point_g, point_b);
            cr.arc (x, y, 5, 0, 2 * Math.PI);
            cr.fill ();
        }
    }

    /**
     * Handles export image button click.
     */
    private void on_export_image_clicked () {
        var png_filter = new Gtk.FileFilter ();
        png_filter.name = "PNG Images";
        png_filter.add_mime_type ("image/png");
        
        var svg_filter = new Gtk.FileFilter ();
        svg_filter.name = "SVG Images";
        svg_filter.add_mime_type ("image/svg+xml");

        var pdf_filter = new Gtk.FileFilter ();
        pdf_filter.name = "PDF Documents";
        pdf_filter.add_mime_type ("application/pdf");

        var filter_list = new ListStore (typeof (Gtk.FileFilter));
        filter_list.append (png_filter);
        filter_list.append (svg_filter);
        filter_list.append (pdf_filter);

        var file_dialog = new Gtk.FileDialog () {
            modal = true,
            initial_name = "daylength_plot.png",
            filters = filter_list
        };

        file_dialog.save.begin (window, null, (obj, res) => {
            try {
                var file = file_dialog.save.end (res);
                if (file != null) {
                    export_plot_image (file.get_path ());
                }
            } catch (Error e) {
                message ("File has not been saved: %s", e.message);
            }
        });
    }

    /**
     * Exports the plot to an image file.
     *
     * @param filepath Destination file path; file extension selects format (.png, .svg, .pdf).
     */
    private void export_plot_image (string filepath) {
        int width = drawing_area.get_width ();
        int height = drawing_area.get_height ();

        if (width <= 0 || height <= 0) {
            width = 800;
            height = 600;
        }

        string? extension = null;
        var last_dot = filepath.last_index_of_char ('.');
        if (last_dot != -1) {
            extension = filepath[last_dot:].down ();
        }

        if (extension == ".svg") {
            var surface = new Cairo.SvgSurface (filepath, width, height);
            var cr = new Cairo.Context (surface);
            draw_day_length_chart (drawing_area, cr, width, height);
        } else if (extension == ".pdf") {
            var surface = new Cairo.PdfSurface (filepath, width, height);
            var cr = new Cairo.Context (surface);
            draw_day_length_chart (drawing_area, cr, width, height);
        } else {
            var surface = new Cairo.ImageSurface (Cairo.Format.RGB24, width, height);
            var cr = new Cairo.Context (surface);
            draw_day_length_chart (drawing_area, cr, width, height);
            surface.write_to_png (filepath);
        }
    }

    /**
     * Handles export CSV button click.
     */
    private void on_export_csv_clicked () {
        var csv_filter = new Gtk.FileFilter ();
        csv_filter.name = "CSV Files";
        csv_filter.add_mime_type ("text/csv");

        var filter_list = new ListStore (typeof (Gtk.FileFilter));
        filter_list.append (csv_filter);

        var file_dialog = new Gtk.FileDialog () {
            modal = true,
            initial_name = "daylength_data.csv",
            filters = filter_list
        };

        file_dialog.save.begin (window, null, (obj, res) => {
            try {
                var file = file_dialog.save.end (res);
                if (file != null) {
                    export_csv (file.get_path ());
                }
            } catch (Error e) {
                message ("File has not been saved: %s", e.message);
            }
        });
    }

    /**
     * Exports data to a CSV file.
     *
     * @param filepath Destination CSV file path.
     */
    private void export_csv (string filepath) {
        try {
            var file = File.new_for_path (filepath);
            var stream = file.replace (null, false, FileCreateFlags.NONE);
            var data_stream = new DataOutputStream (stream);

            // Write header
            data_stream.put_string ("# Day Length Data\n");
            data_stream.put_string ("# Latitude: %.2f degrees\n".printf (latitude));
            data_stream.put_string ("# Longitude: %.2f degrees\n".printf (longitude));
            data_stream.put_string ("# Timezone: UTC%+.2f\n".printf (timezone_offset_hours));
            data_stream.put_string ("# Horizon Angle: %.2f degrees\n".printf (horizon_angle));
            data_stream.put_string ("#\n");
            data_stream.put_string ("DayOfYear,Date,DayLength(hours),Sunrise,Sunset\n");
            // Write data
            for (int i = 0; i < day_lengths.length; i += 1) {
                var date = new DateTime (new TimeZone.local (), selected_year, 1, 1, 0, 0, 0).add_days (i);
                string date_str = date.format ("%Y-%m-%d");

                string sunrise_str, sunset_str;
                if (sunrise_times[i].is_nan () || sunset_times[i].is_nan ()) {
                    sunrise_str = "N/A";
                    sunset_str = "N/A";
                } else {
                    double sunrise_parts = sunrise_times[i];
                    int sunrise_h = (int) sunrise_parts;
                    sunrise_parts -= sunrise_h;
                    int sunrise_m = (int) (sunrise_parts * 60);
                    sunrise_parts -= ((double) sunrise_m / 60.0);
                    int sunrise_s = (int) (sunrise_parts * 3600);
                    sunrise_str = "%02d:%02d:%02d".printf (sunrise_h, sunrise_m, sunrise_s);

                    double sunset_parts = sunset_times[i];
                    int sunset_h = (int) sunset_parts;
                    sunset_parts -= sunset_h;
                    int sunset_m = (int) (sunset_parts * 60);
                    sunset_parts -= ((double) sunset_m / 60.0);
                    int sunset_s = (int) (sunset_parts * 3600);
                    sunset_str = "%02d:%02d:%02d".printf (sunset_h, sunset_m, sunset_s);
                }

                data_stream.put_string ("%d,%s,%.3f,%s,%s\n".printf (i + 1, date_str, day_lengths[i], sunrise_str, sunset_str));
            }

            data_stream.close ();
        } catch (Error e) {
            show_error_dialog ("Export Failed", e.message);
        }
    }
}

/**
 * Main entry point.
 */
public static int main (string[] args) {
    var app = new DayLengthApp ();
    return app.run (args);
}
