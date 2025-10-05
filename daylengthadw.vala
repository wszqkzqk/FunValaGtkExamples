#!/usr/bin/env -S vala --pkg=gtk4 --pkg=libadwaita-1 --pkg=json-glib-1.0 -X -lm -X -O2 -X -march=native -X -pipe
/* SPDX-License-Identifier: LGPL-2.1-or-later */

/**
 * Day Length Calculator Application with Simplified Solar Formula.
 * Copyright (C) 2025 wszqkzqk <wszqkzqk@qq.com>
 * 
 * A libadwaita application that calculates and visualizes day length
 * throughout the year using astronomical formulas based on solar declination.
 */
public class DayLengthApp : Adw.Application {
    // Constants
    private const double DEG2RAD = Math.PI / 180.0;
    private const double RAD2DEG = 180.0 / Math.PI;
    private const int MARGIN_LEFT = 70;
    private const int MARGIN_RIGHT = 20;
    private const int MARGIN_TOP = 50;
    private const int MARGIN_BOTTOM = 70;

    // Model / persistent state
    private double latitude = 0.0;
    private int selected_year;
    private double horizon_angle = -0.83; // Refraction-corrected horizon angle in degrees
    private double[] day_lengths; // Hours of daylight for each day
    private int clicked_day = -1; // Selected day on chart
    private bool has_click_point = false;

    // UI widgets
    private Adw.ApplicationWindow window;
    private Gtk.DrawingArea drawing_area;
    private Gtk.Label click_info_label;
    private Gtk.Stack location_stack;
    private Gtk.Spinner location_spinner;
    private Gtk.Button location_button;
    private Adw.SpinRow latitude_row;
    private Adw.SpinRow year_row;
    private Adw.SpinRow horizon_row;

    // Color theme struct for chart drawing
    private struct ThemeColors {
        double bg_r; double bg_g; double bg_b;
        double grid_r; double grid_g; double grid_b; double grid_a;
        double axis_r; double axis_g; double axis_b;
        double text_r; double text_g; double text_b;
        double curve_r; double curve_g; double curve_b;
        double point_r; double point_g; double point_b;
        double line_r; double line_g; double line_b; double line_a;
    }

    private static ThemeColors LIGHT_THEME = {
        bg_r: 1.0, bg_g: 1.0, bg_b: 1.0,
        grid_r: 0.5, grid_g: 0.5, grid_b: 0.5, grid_a: 0.5,
        axis_r: 0.0, axis_g: 0.0, axis_b: 0.0,
        text_r: 0.0, text_g: 0.0, text_b: 0.0,
        curve_r: 1.0, curve_g: 0.5, curve_b: 0.0,
        point_r: 0.0, point_g: 0.0, point_b: 1.0,
        line_r: 0.0, line_g: 0.0, line_b: 1.0, line_a: 0.5
    };

    private static ThemeColors DARK_THEME = {
        bg_r: 0.0, bg_g: 0.0, bg_b: 0.0,
        grid_r: 0.5, grid_g: 0.5, grid_b: 0.5, grid_a: 0.5,
        axis_r: 1.0, axis_g: 1.0, axis_b: 1.0,
        text_r: 1.0, text_g: 1.0, text_b: 1.0,
        curve_r: 1.0, curve_g: 0.5, curve_b: 0.0,
        point_r: 0.3, point_g: 0.7, point_b: 1.0,
        line_r: 0.3, line_g: 0.7, line_b: 1.0, line_a: 0.7
    };

    /**
     * Creates a new DayLengthApp instance.
     */
    public DayLengthApp () {
        Object (application_id: "com.github.wszqkzqk.DayLengthAdw");
        DateTime now = new DateTime.now_local ();
        selected_year = now.get_year ();
    }

    /**
     * Activates the application and creates the main window.
     */
    protected override void activate () {
        window = new Adw.ApplicationWindow (this) {
            title = "Day Length Calculator",
        };

        var header_bar = new Adw.HeaderBar () {
            title_widget = new Adw.WindowTitle ("Day Length Calculator", ""),
        };

        // Dark mode toggle
        var dark_mode_button = new Gtk.ToggleButton () {
            icon_name = "weather-clear-night-symbolic",
            tooltip_text = "Toggle dark mode",
            active = style_manager.dark,
        };
        dark_mode_button.toggled.connect (() => {
            style_manager.color_scheme = (dark_mode_button.active) ? Adw.ColorScheme.FORCE_DARK : Adw.ColorScheme.FORCE_LIGHT;
            drawing_area.queue_draw ();
        });

        style_manager.notify["dark"].connect (() => {
            drawing_area.queue_draw ();
        });

        header_bar.pack_end (dark_mode_button);

        var toolbar_view = new Adw.ToolbarView ();
        toolbar_view.add_top_bar (header_bar);

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

        // Location and Time Settings Group
        var location_time_group = new Adw.PreferencesGroup () {
            title = "Location Settings",
        };

        // Auto-detect location button
        var location_detect_row = new Adw.ActionRow () {
            title = "Auto-detect Location",
            subtitle = "Get current latitude",
            activatable = true,
        };

        var location_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        location_stack = new Gtk.Stack () {
            hhomogeneous = true,
            vhomogeneous = true,
            transition_type = Gtk.StackTransitionType.CROSSFADE,
        };
        location_spinner = new Gtk.Spinner ();
        location_button = new Gtk.Button () {
            icon_name = "find-location-symbolic",
            valign = Gtk.Align.CENTER,
            css_classes = { "flat" },
            tooltip_text = "Auto-detect current location",
        };
        location_button.clicked.connect (on_auto_detect_location);
        location_stack.add_child (location_button);
        location_stack.add_child (location_spinner);
        location_stack.visible_child = location_button;
        location_box.append (location_stack);
        location_detect_row.add_suffix (location_box);
        location_detect_row.activated.connect (on_auto_detect_location);

        latitude_row = new Adw.SpinRow.with_range (-90, 90, 0.1) {
            title = "Latitude",
            subtitle = "Degrees",
            value = latitude,
            digits = 2,
        };
        latitude_row.notify["value"].connect (() => {
            latitude = latitude_row.value;
            update_plot_data ();
            drawing_area.queue_draw ();
        });

        location_time_group.add (location_detect_row);
        location_time_group.add (latitude_row);

        // Horizon angle row
        horizon_row = new Adw.SpinRow.with_range (-5, 5, 0.01) {
            title = "Horizon Angle",
            subtitle = "Degrees",
            value = horizon_angle,
            digits = 2,
        };
        horizon_row.notify["value"].connect (() => {
            horizon_angle = horizon_row.value;
            update_plot_data ();
            drawing_area.queue_draw ();
        });

        location_time_group.add (horizon_row);

        // Year Selection Group
        var year_group = new Adw.PreferencesGroup () {
            title = "Year Selection",
        };

        year_row = new Adw.SpinRow.with_range (1, 9999, 1) {
            title = "Year",
            subtitle = "Calendar year",
            value = selected_year,
            digits = 0,
        };
        year_row.notify["value"].connect (() => {
            selected_year = (int) year_row.value;
            update_plot_data ();
            drawing_area.queue_draw ();
        });

        year_group.add (year_row);

        // Export Group
        var export_group = new Adw.PreferencesGroup () {
            title = "Export",
        };

        var export_image_row = new Adw.ActionRow () {
            title = "Export Image",
            subtitle = "Save chart as PNG, SVG, or PDF",
            activatable = true,
        };
        var export_image_button = new Gtk.Button () {
            icon_name = "document-save-symbolic",
            valign = Gtk.Align.CENTER,
            css_classes = { "flat" },
        };
        export_image_button.clicked.connect (on_export_image_clicked);
        export_image_row.add_suffix (export_image_button);
        export_image_row.activated.connect (on_export_image_clicked);

        var export_csv_row = new Adw.ActionRow () {
            title = "Export CSV",
            subtitle = "Save data as CSV file",
            activatable = true,
        };
        var export_csv_button = new Gtk.Button () {
            icon_name = "x-office-spreadsheet-symbolic",
            valign = Gtk.Align.CENTER,
            css_classes = { "flat" },
        };
        export_csv_button.clicked.connect (on_export_csv_clicked);
        export_csv_row.add_suffix (export_csv_button);
        export_csv_row.activated.connect (on_export_csv_clicked);

        export_group.add (export_image_row);
        export_group.add (export_csv_row);

        // Click Info Group
        var click_info_group = new Adw.PreferencesGroup () {
            title = "Selected Day",
        };

        click_info_label = new Gtk.Label ("Click on chart to view data\n") {
            halign = Gtk.Align.START,
            margin_start = 12,
            margin_end = 12,
            margin_top = 6,
            margin_bottom = 6,
            wrap = true,
        };

        var click_info_row = new Adw.ActionRow ();
        click_info_row.child = click_info_label;
        click_info_group.add (click_info_row);

        left_panel.append (location_time_group);
        left_panel.append (year_group);
        left_panel.append (export_group);
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

        toolbar_view.content = main_box;

        update_plot_data ();

        window.content = toolbar_view;
        window.present ();
    }

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
        double gamma_rad = (2.0 * Math.PI / days_in_year_val) * (day_of_year - 1);
        
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
        
        // Handle polar day and polar night
        if (cos_hour_angle > 1.0) {
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
     * Updates plot data for all days in the selected year.
     */
    private void update_plot_data () {
        int total_days = days_in_year (selected_year);
        day_lengths = new double[total_days];
        
        double latitude_rad = latitude * DEG2RAD;

        for (int day = 1; day <= total_days; day += 1) {
            day_lengths[day - 1] = calculate_day_length_simplified (
                latitude_rad, day, selected_year, horizon_angle
            );
        }

        // Clear click point when data updates
        has_click_point = false;
        click_info_label.label = "Click on chart to view data\n";
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

        latitude_row.value = latitude;
        update_plot_data ();
        drawing_area.queue_draw ();
    }

    /**
     * Shows an error dialog.
     */
    private void show_error_dialog (string title, string error_message) {
        var dialog = new Adw.AlertDialog (title, error_message);
        dialog.add_response ("ok", "OK");
        dialog.present (window);
        message ("%s: %s", title, error_message);
    }

    /**
     * Handles mouse click events on the chart.
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
            string date_str = date.format ("%B %d");
            
            string info_text = "Date: %s (Day %d)\nDay Length: %.2f hours".printf (
                date_str, clicked_day + 1, day_lengths[clicked_day]
            );

            click_info_label.label = info_text;
            drawing_area.queue_draw ();
        } else {
            has_click_point = false;
            click_info_label.label = "Click on chart to view data";
            drawing_area.queue_draw ();
        }
    }

    /**
     * Draws the day length chart.
     */
    private void draw_day_length_chart (Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
        ThemeColors colors = style_manager.dark ? DARK_THEME : LIGHT_THEME;

        // Fill background
        cr.set_source_rgb (colors.bg_r, colors.bg_g, colors.bg_b);
        cr.paint ();

        int chart_width = width - MARGIN_LEFT - MARGIN_RIGHT;
        int chart_height = height - MARGIN_TOP - MARGIN_BOTTOM;
        int total_days = day_lengths.length;

        double y_min = -0.5, y_max = 24.5;

        // Draw grid lines
        cr.set_source_rgba (colors.grid_r, colors.grid_g, colors.grid_b, colors.grid_a);
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
        cr.set_source_rgb (colors.axis_r, colors.axis_g, colors.axis_b);
        cr.set_line_width (2.0);
        cr.move_to (MARGIN_LEFT, height - MARGIN_BOTTOM);
        cr.line_to (width - MARGIN_RIGHT, height - MARGIN_BOTTOM);
        cr.stroke ();
        cr.move_to (MARGIN_LEFT, MARGIN_TOP);
        cr.line_to (MARGIN_LEFT, height - MARGIN_BOTTOM);
        cr.stroke ();

        // Draw Y axis ticks and labels
        cr.set_source_rgb (colors.text_r, colors.text_g, colors.text_b);
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
        string caption = "Day Length - Latitude: %.2f°, Year: %d, Horizon: %.2f°".printf (
            latitude, selected_year, horizon_angle
        );
        cr.set_font_size (18);
        var cap_te = Cairo.TextExtents ();
        cr.text_extents (caption, out cap_te);
        cr.move_to ((width - cap_te.width) / 2, (double) MARGIN_TOP / 2);
        cr.show_text (caption);

        // Draw data curve
        cr.set_source_rgb (colors.curve_r, colors.curve_g, colors.curve_b);
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
            cr.set_source_rgba (colors.line_r, colors.line_g, colors.line_b, colors.line_a);
            cr.set_line_width (1.5);
            cr.move_to (x, MARGIN_TOP);
            cr.line_to (x, height - MARGIN_BOTTOM);
            cr.stroke ();

            // Draw horizontal guide line
            cr.move_to (MARGIN_LEFT, y);
            cr.line_to (width - MARGIN_RIGHT, y);
            cr.stroke ();

            // Draw point
            cr.set_source_rgb (colors.point_r, colors.point_g, colors.point_b);
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
     */
    private void export_csv (string filepath) {
        try {
            var file = File.new_for_path (filepath);
            var stream = file.replace (null, false, FileCreateFlags.NONE);
            var data_stream = new DataOutputStream (stream);

            // Write header
            data_stream.put_string ("Day of Year,Date,Day Length (hours)\n");

            // Write data
            for (int i = 0; i < day_lengths.length; i += 1) {
                var date = new DateTime (new TimeZone.local (), selected_year, 1, 1, 0, 0, 0).add_days (i);
                string date_str = date.format ("%Y-%m-%d");
                data_stream.put_string ("%d,%s,%.6f\n".printf (i + 1, date_str, day_lengths[i]));
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
