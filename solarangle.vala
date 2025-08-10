#!/usr/bin/env -S vala --pkg=gtk4 --pkg=libadwaita-1 --pkg=json-glib-1.0 -X -lm -X -O2 -X -march=native -X -pipe
/* SPDX-License-Identifier: LGPL-2.1-or-later */

/**
 * Solar Angle Calculator Application.
 *
 * A libadwaita application that calculates and visualizes solar elevation angles
 * throughout the day for a given location and date. The application provides
 * an interactive interface for setting latitude, longitude, timezone, and date,
 * and displays a real-time chart of solar elevation angles with export capabilities.
 */
public class SolarAngleApp : Adw.Application {
    // Constants for solar angle calculations
    private const double DEG2RAD = Math.PI / 180.0;
    private const double RAD2DEG = 180.0 / Math.PI;
    private const int RESOLUTION_PER_MIN = 1440; // 1 sample per minute
    // Constants for drawing area
    private const int MARGIN_LEFT = 70;
    private const int MARGIN_RIGHT = 20;
    private const int MARGIN_TOP = 50;
    private const int MARGIN_BOTTOM = 70;

    private Adw.ApplicationWindow window;
    private Gtk.DrawingArea drawing_area;
    private Gtk.Label click_info_label;
    private DateTime selected_date;
    private double sun_angles[RESOLUTION_PER_MIN];
    private double latitude = 0.0;
    private double longitude = 0.0;
    private double timezone_offset_hours = 0.0;
    private double clicked_time_hours = 0.0;
    private double corresponding_angle = 0.0;
    private bool has_click_point = false;

    // Location detection widgets
    private Gtk.Stack location_stack;
    private Gtk.Spinner location_spinner;
    private Gtk.Button location_button;
    private Adw.SpinRow latitude_row;
    private Adw.SpinRow longitude_row;
    private Adw.SpinRow timezone_row;

    // Color theme struct for chart drawing
    private struct ThemeColors {
        // Background colors
        double bg_r; double bg_g; double bg_b;
        // Grid colors with alpha
        double grid_r; double grid_g; double grid_b; double grid_a;
        // Axis colors
        double axis_r; double axis_g; double axis_b;
        // Text colors
        double text_r; double text_g; double text_b;
        // Curve colors
        double curve_r; double curve_g; double curve_b;
        // Shaded area colors with alpha
        double shade_r; double shade_g; double shade_b; double shade_a;
        // Click point colors
        double point_r; double point_g; double point_b;
        // Guide line colors with alpha
        double line_r; double line_g; double line_b; double line_a;
    }

    // Light theme color constants
    private ThemeColors LIGHT_THEME = {
        bg_r: 1.0, bg_g: 1.0, bg_b: 1.0,                    // White background
        grid_r: 0.5, grid_g: 0.5, grid_b: 0.5, grid_a: 0.5, // Gray grid
        axis_r: 0.0, axis_g: 0.0, axis_b: 0.0,              // Black axes
        text_r: 0.0, text_g: 0.0, text_b: 0.0,              // Black text
        curve_r: 1.0, curve_g: 0.0, curve_b: 0.0,           // Red curve
        shade_r: 0.7, shade_g: 0.7, shade_b: 0.7, shade_a: 0.3, // Light gray shade
        point_r: 0.0, point_g: 0.0, point_b: 1.0,           // Blue point
        line_r: 0.0, line_g: 0.0, line_b: 1.0, line_a: 0.5  // Blue guide lines
    };

    // Dark theme color constants
    private ThemeColors DARK_THEME = {
        bg_r: 0.0, bg_g: 0.0, bg_b: 0.0,                    // Black background
        grid_r: 0.5, grid_g: 0.5, grid_b: 0.5, grid_a: 0.5, // Light gray grid
        axis_r: 1.0, axis_g: 1.0, axis_b: 1.0,              // White axes
        text_r: 1.0, text_g: 1.0, text_b: 1.0,              // White text
        curve_r: 1.0, curve_g: 0.0, curve_b: 0.0,           // Bright red curve
        shade_r: 0.3, shade_g: 0.3, shade_b: 0.3, shade_a: 0.7, // Dark gray shade
        point_r: 0.3, point_g: 0.7, point_b: 1.0,           // Light blue point
        line_r: 0.3, line_g: 0.7, line_b: 1.0, line_a: 0.7  // Light blue guide lines
    };

    /**
     * Creates a new SolarAngleApp instance.
     *
     * Initializes the application with a unique application ID and sets
     * the selected date to the current local date.
     */
    public SolarAngleApp () {
        Object (application_id: "com.github.wszqkzqk.SolarAngleAdw");
        selected_date = new DateTime.now_local ();
    }

    /**
     * Activates the application and creates the main window.
     *
     * Sets up the user interface including input controls, drawing area,
     * and initializes the plot data with current settings.
     */
    protected override void activate () {
        window = new Adw.ApplicationWindow (this) {
            title = "Solar Angle Calculator",
        };

        // Create header bar
        var header_bar = new Adw.HeaderBar () {
            title_widget = new Adw.WindowTitle ("Solar Angle Calculator", ""),
        };

        // Add dark mode toggle button
        var dark_mode_button = new Gtk.ToggleButton () {
            icon_name = "weather-clear-night-symbolic",
            tooltip_text = "Toggle dark mode",
            active = style_manager.dark,
        };
        dark_mode_button.toggled.connect (() => {
            if (dark_mode_button.active) {
                style_manager.color_scheme = Adw.ColorScheme.FORCE_DARK;
            } else {
                style_manager.color_scheme = Adw.ColorScheme.FORCE_LIGHT;
            }
            drawing_area.queue_draw ();
        });

        // Listen for system theme changes
        style_manager.notify["dark"].connect (() => {
            drawing_area.queue_draw ();
        });

        header_bar.pack_end (dark_mode_button);

        // Create toolbar view to hold header bar and content
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
            title = "Location and Time Settings",
        };

        // Auto-detect location button
        var location_detect_row = new Adw.ActionRow () {
            title = "Auto-detect Location",
            subtitle = "Get current location and timezone",
            activatable = true,
        };

        var location_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        // Use a stack to keep consistent allocation and avoid layout jitter
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
        // Add to stack as separate pages
        location_stack.add_child (location_button);
        location_stack.add_child (location_spinner);
        location_stack.visible_child = location_button;
        // Place stack into the suffix box
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

        longitude_row = new Adw.SpinRow.with_range (-180.0, 180.0, 0.1) {
            title = "Longitude",
            subtitle = "Degrees",
            value = longitude,
            digits = 2,
        };
        longitude_row.notify["value"].connect (() => {
            longitude = longitude_row.value;
            update_plot_data ();
            drawing_area.queue_draw ();
        });

        timezone_row = new Adw.SpinRow.with_range (-12.0, 14.0, 0.5) {
            title = "Timezone",
            subtitle = "Hours from UTC",
            value = timezone_offset_hours,
            digits = 2,
        };
        timezone_row.notify["value"].connect (() => {
            timezone_offset_hours = timezone_row.value;
            update_plot_data ();
            drawing_area.queue_draw ();
        });

        location_time_group.add (location_detect_row);
        location_time_group.add (latitude_row);
        location_time_group.add (longitude_row);
        location_time_group.add (timezone_row);

        // Date Selection Group
        var date_group = new Adw.PreferencesGroup () {
            title = "Date Selection",
        };

        var calendar = new Gtk.Calendar () {
            margin_start = 12,
            margin_end = 12,
            margin_top = 6,
            margin_bottom = 6,
        };
        calendar.day_selected.connect (() => {
            selected_date = calendar.get_date ();
            update_plot_data ();
            drawing_area.queue_draw ();
        });

        var calendar_row = new Adw.ActionRow ();
        calendar_row.child = calendar;
        date_group.add (calendar_row);

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
        export_image_button.clicked.connect (on_export_clicked);
        export_image_row.add_suffix (export_image_button);
        export_image_row.activated.connect (on_export_clicked);

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
            title = "Selected Point",
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
        left_panel.append (date_group);
        left_panel.append (export_group);
        left_panel.append (click_info_group);

        drawing_area = new Gtk.DrawingArea () {
            hexpand = true,
            vexpand = true,
            width_request = 600,
            height_request = 500,
        };
        drawing_area.set_draw_func (draw_sun_angle_chart);

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
     * Handles auto-detect location button click.
     * 
     * Uses a free IP geolocation service to get current location and timezone.
     */
    private void on_auto_detect_location () {
        location_button.sensitive = false;
        // Switch to spinner page without changing allocation size
        location_stack.visible_child = location_spinner;
        location_spinner.start ();

         // Run async to avoid blocking the UI
         get_location_async.begin ((obj, res) => {
            try {
                get_location_async.end (res);
            } catch (Error e) {
                show_error_dialog ("Location Detection Failed", e.message);
            }

            location_button.sensitive = true;
            location_spinner.stop ();
            // Switch back to button page
            location_stack.visible_child = location_button;
         });
     }

    /**
     * Asynchronously gets current location using IP geolocation service with timeout.
     */
    private async void get_location_async () throws IOError {
        var file = File.new_for_uri ("https://ipapi.co/json/");
        var cancellable = new Cancellable ();

        // Set up a 5-second timeout
        Timeout.add_seconds (5, () => {
            cancellable.cancel ();
            return false;
        });

        try {
            var stream = yield file.read_async (Priority.DEFAULT, cancellable);
            var parser = new Json.Parser ();
            yield parser.load_from_stream_async (stream, cancellable);

            var root_object = parser.get_root ().get_object ();
            if (root_object.get_boolean_member_with_default ("error", false)) {
                throw new IOError.FAILED ("Location service error: %s", root_object.get_string_member_with_default ("reason", "Unknown error"));
            }

            if (root_object.has_member ("latitude") && root_object.has_member ("longitude")) {
                latitude = root_object.get_double_member ("latitude");
                longitude = root_object.get_double_member ("longitude");
            } else {
                throw new IOError.FAILED ("No coordinates found in the response");
            }

            double network_tz_offset = 0.0;
            bool has_network_tz = false;

            if (root_object.has_member ("utc_offset")) {
                var offset_str = root_object.get_string_member ("utc_offset");
                network_tz_offset = double.parse (offset_str) / 100.0;
                has_network_tz = true;
            }

            // Get local system's current timezone offset
            var timezone = new TimeZone.local ();
            var time_interval = timezone.find_interval (GLib.TimeType.UNIVERSAL, selected_date.to_unix ());
            var local_tz_offset = timezone.get_offset (time_interval) / 3600.0;

            const double TZ_EPSILON = 0.01; // Epsilon for floating point comparison
            if (has_network_tz && (!(-TZ_EPSILON < (network_tz_offset - local_tz_offset) < TZ_EPSILON))) {
                const string RESPONSE_NETWORK = "network"; // ID for network timezone
                const string RESPONSE_LOCAL = "local"; // ID for local timezone

                // Timezones differ, prompt user for a choice
                var dialog = new Adw.AlertDialog (
                    "Timezone Mismatch",
                    "The timezone from the network (UTC%+.2f) differs from your system's timezone (UTC%+.2f).\n\nWhich one would you like to use?".printf (
                        network_tz_offset,
                        local_tz_offset
                    )
                );
                dialog.add_response (RESPONSE_NETWORK, "Use Network Timezone");
                dialog.add_response (RESPONSE_LOCAL, "Use System Timezone");
                dialog.default_response = RESPONSE_NETWORK;

                // Asynchronously wait for the user's choice
                string choice = yield dialog.choose (window, null);

                if (choice == RESPONSE_NETWORK) {
                    timezone_offset_hours = network_tz_offset;
                } else {
                    timezone_offset_hours = local_tz_offset;
                }
            } else {
                // Network's timezone is the same as local's or unavailable
                timezone_offset_hours = local_tz_offset;
            }

            Idle.add (() => {
                latitude_row.value = latitude;
                longitude_row.value = longitude;
                timezone_row.value = timezone_offset_hours;
                update_plot_data ();
                drawing_area.queue_draw ();
                return false;
            });
        } catch (Error e) {
            throw new IOError.FAILED ("Failed to get location: %s", e.message);
        }
    }

    /**
     * Shows a generic error dialog and logs the error message.
     *
     * @param title The title of the error dialog.
     * @param error_message The error message to display.
     */
    private void show_error_dialog (string title, string error_message) {
        var dialog = new Adw.AlertDialog (title, error_message);
        dialog.add_response ("ok", "OK");
        dialog.present (window);
        message ("%s: %s", title, error_message);
    }

    /**
     * Calculates solar elevation angles for each minute of the day.
     *
     * @param latitude_rad Latitude in radians.
     * @param day_of_year Day of the year (1-365/366).
     * @param year The year.
     * @param longitude_deg Longitude in degrees.
     * @param timezone_offset_hrs Timezone offset from UTC in hours.
     */
    private void generate_sun_angles (double latitude_rad, int day_of_year, int year, double longitude_deg, double timezone_offset_hrs) {
        double sin_lat = Math.sin (latitude_rad);
        double cos_lat = Math.cos (latitude_rad);

        double days_in_year = ((year % 4 == 0) && ((year % 100 != 0) || (year % 400 == 0))) ? 366.0 : 365.0;

        for (int i = 0; i < RESOLUTION_PER_MIN; i += 1) {
            // fractional_day_component: day of year plus fraction of the day
            double fractional_day_component = day_of_year - 1 + ((double) i) / RESOLUTION_PER_MIN;
            // gamma: fractional year angle in radians
            double gamma_rad = (2.0 * Math.PI / days_in_year) * fractional_day_component;

            // Solar declination delta (rad) via Fourier series approximation
            double decl_rad = 0.006918
                - 0.399912 * Math.cos (gamma_rad)
                + 0.070257 * Math.sin (gamma_rad)
                - 0.006758 * Math.cos (2.0 * gamma_rad)
                + 0.000907 * Math.sin (2.0 * gamma_rad)
                - 0.002697 * Math.cos (3.0 * gamma_rad)
                + 0.001480 * Math.sin (3.0 * gamma_rad);

            // Equation of Time (EoT) in minutes
            double eqtime_minutes = 229.18 * (0.000075
                + 0.001868 * Math.cos (gamma_rad)
                - 0.032077 * Math.sin (gamma_rad)
                - 0.014615 * Math.cos (2.0 * gamma_rad)
                - 0.040849 * Math.sin (2.0 * gamma_rad));

            // True Solar Time (TST) in minutes, correcting local clock by EoT and longitude
            double tst_minutes = i + eqtime_minutes + 4.0 * longitude_deg - 60.0 * timezone_offset_hrs;

            // Hour angle H (°) relative to solar noon
            double ha_deg = tst_minutes / 4.0 - 180.0;
            double ha_rad = ha_deg * DEG2RAD;

            // cos(phi): cosine of zenith angle via spherical trig
            double cos_phi = sin_lat * Math.sin (decl_rad) + cos_lat * Math.cos (decl_rad) * Math.cos (ha_rad);
            // clamp to valid range
            if (cos_phi > 1.0) {
                cos_phi = 1.0;
            } else if (cos_phi < -1.0) {
                cos_phi = -1.0;
            }
            // Zenith angle phi (rad)
            double phi_rad = Math.acos (cos_phi);

            // Solar elevation alpha = 90° - phi, convert to degrees
            double solar_elevation_rad = Math.PI / 2.0 - phi_rad;
            sun_angles[i] = solar_elevation_rad * RAD2DEG;
        }
    }

    /**
     * Updates solar angle data for current settings.
     */
    private void update_plot_data () {
        int day_of_year = selected_date.get_day_of_year ();
        double latitude_rad = latitude * DEG2RAD;
        int year = selected_date.get_year ();
        generate_sun_angles (latitude_rad, day_of_year, year, longitude, timezone_offset_hours);
        
        // Clear click point when data updates
        has_click_point = false;
        click_info_label.label = "Click on chart to view data\n";
    }

    /**
     * Handles mouse click events on the chart.
     *
     * @param n_press Number of button presses.
     * @param x X coordinate of the click.
     * @param y Y coordinate of the click.
     */
    private void on_chart_clicked (int n_press, double x, double y) {
        int width = drawing_area.get_width ();
        int height = drawing_area.get_height ();

        int chart_width = width - MARGIN_LEFT - MARGIN_RIGHT;

        // Check if click is within plot area and single click
        if (x >= MARGIN_LEFT && x <= width - MARGIN_RIGHT && y >= MARGIN_TOP && y <= height - MARGIN_BOTTOM && n_press == 1) {
            // Convert coordinates to time and get corresponding angle
            clicked_time_hours = (x - MARGIN_LEFT) / chart_width * 24.0;
            int time_minutes = (int) (clicked_time_hours * 60) % RESOLUTION_PER_MIN;
            corresponding_angle = sun_angles[time_minutes];
            has_click_point = true;

            // Format time display
            int hours = (int) clicked_time_hours;
            int minutes = (int) ((clicked_time_hours - hours) * 60);

            // Update info label
            string info_text = "Time: %02d:%02d\nSolar Elevation: %.1f°".printf (
                hours, minutes, corresponding_angle
            );

            click_info_label.label = info_text;
            drawing_area.queue_draw ();
        } else {
            // Double click or outside plot area - clear point
            has_click_point = false;
            click_info_label.label = "Click on chart to view data\n";
            drawing_area.queue_draw ();
        }
    }

    /**
     * Draws the solar elevation chart.
     *
     * @param area The drawing area widget.
     * @param cr The Cairo context for drawing.
     * @param width The width of the drawing area.
     * @param height The height of the drawing area.
     */
    private void draw_sun_angle_chart (Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
        ThemeColors colors = style_manager.dark ? DARK_THEME : LIGHT_THEME;

        // Fill background
        cr.set_source_rgb (colors.bg_r, colors.bg_g, colors.bg_b);
        cr.paint ();

        int chart_width = width - MARGIN_LEFT - MARGIN_RIGHT;
        int chart_height = height - MARGIN_TOP - MARGIN_BOTTOM;

        double horizon_y = MARGIN_TOP + chart_height * 0.5; // 0° is at middle of -90° to +90° range
        
        // Shade area below horizon
        cr.set_source_rgba (colors.shade_r, colors.shade_g, colors.shade_b, colors.shade_a);
        cr.rectangle (MARGIN_LEFT, horizon_y, chart_width, height - MARGIN_BOTTOM - horizon_y);
        cr.fill ();

        // Draw horizontal grid every 15°
        cr.set_source_rgba (colors.grid_r, colors.grid_g, colors.grid_b, colors.grid_a);
        cr.set_line_width (1);
        for (int angle = -90; angle <= 90; angle += 15) {
            double tick_y = MARGIN_TOP + chart_height * (90 - angle) / 180.0;
            cr.move_to (MARGIN_LEFT, tick_y);
            cr.line_to (width - MARGIN_RIGHT, tick_y);
            cr.stroke ();
        }
        // Draw vertical grid every 2 hours
        for (int h = 0; h <= 24; h += 2) {
            double tick_x = MARGIN_LEFT + chart_width * (h / 24.0);
            cr.move_to (tick_x, MARGIN_TOP);
            cr.line_to (tick_x, height - MARGIN_BOTTOM);
            cr.stroke ();
        }

        // Draw axes and horizon
        cr.set_source_rgb (colors.axis_r, colors.axis_g, colors.axis_b);
        cr.set_line_width (2);
        cr.move_to (MARGIN_LEFT, height - MARGIN_BOTTOM);
        cr.line_to (width - MARGIN_RIGHT, height - MARGIN_BOTTOM);
        cr.stroke ();
        cr.move_to (MARGIN_LEFT, MARGIN_TOP);
        cr.line_to (MARGIN_LEFT, height - MARGIN_BOTTOM);
        cr.stroke ();
        // Horizon line
        cr.move_to (MARGIN_LEFT, horizon_y);
        cr.line_to (width - MARGIN_RIGHT, horizon_y);
        cr.stroke ();

        // Draw axis ticks and labels
        cr.set_source_rgb (colors.text_r, colors.text_g, colors.text_b);
        cr.set_line_width (1);
        cr.set_font_size (20);
        for (int angle = -90; angle <= 90; angle += 15) {
            double tick_y = MARGIN_TOP + chart_height * (90 - angle) / 180.0;
            cr.move_to (MARGIN_LEFT - 5, tick_y);
            cr.line_to (MARGIN_LEFT, tick_y);
            cr.stroke ();
            var te = Cairo.TextExtents ();
            var txt = angle.to_string ();
            cr.text_extents (txt, out te);
            cr.move_to (MARGIN_LEFT - 10 - te.width, tick_y + te.height / 2);
            cr.show_text (txt);
        }
        for (int h = 0; h <= 24; h += 2) {
            double tick_x = MARGIN_LEFT + chart_width * (h / 24.0);
            cr.move_to (tick_x, height - MARGIN_BOTTOM);
            cr.line_to (tick_x, height - MARGIN_BOTTOM + 5);
            cr.stroke ();
            var te = Cairo.TextExtents ();
            var txt = h.to_string ();
            cr.text_extents (txt, out te);
            cr.move_to (tick_x - te.width / 2, height - MARGIN_BOTTOM + 25);
            cr.show_text (txt);
        }

        // Plot solar elevation curve
        cr.set_source_rgb (colors.curve_r, colors.curve_g, colors.curve_b);
        cr.set_line_width (2);
        for (int i = 0; i < RESOLUTION_PER_MIN; i += 1) {
            double x = MARGIN_LEFT + chart_width * (i / (double) (RESOLUTION_PER_MIN - 1));
            double y = MARGIN_TOP + chart_height * (90.0 - sun_angles[i]) / 180.0;
            if (i == 0) {
                cr.move_to (x, y);
            } else {
                cr.line_to (x, y);
            }
        }
        cr.stroke ();

        // Draw click point if exists
        if (has_click_point) {
            // Calculate current coordinates from stored time and angle
            double clicked_x = MARGIN_LEFT + chart_width * (clicked_time_hours / 24.0);
            double corresponding_y = MARGIN_TOP + chart_height * (90.0 - corresponding_angle) / 180.0;

            cr.set_source_rgba (colors.point_r, colors.point_g, colors.point_b, 0.8);
            cr.arc (clicked_x, corresponding_y, 5, 0, 2 * Math.PI);
            cr.fill ();
            
            // Draw vertical line to show time
            cr.set_source_rgba (colors.line_r, colors.line_g, colors.line_b, colors.line_a);
            cr.set_line_width (1);
            cr.move_to (clicked_x, MARGIN_TOP);
            cr.line_to (clicked_x, height - MARGIN_BOTTOM);
            cr.stroke ();
            
            // Draw horizontal line to show angle
            cr.move_to (MARGIN_LEFT, corresponding_y);
            cr.line_to (width - MARGIN_RIGHT, corresponding_y);
            cr.stroke ();
        }

        // Draw axis titles
        cr.set_source_rgb (colors.text_r, colors.text_g, colors.text_b);
        cr.set_font_size (20);
        string x_title = "Time (hours)";
        Cairo.TextExtents x_ext;
        cr.text_extents (x_title, out x_ext);
        cr.move_to ((double) width / 2 - x_ext.width / 2, height - MARGIN_BOTTOM + 55);
        cr.show_text (x_title);
        string y_title = "Solar Elevation (°)";
        Cairo.TextExtents y_ext;
        cr.text_extents (y_title, out y_ext);
        cr.save ();
        cr.translate (MARGIN_LEFT - 45, (double)height / 2);
        cr.rotate (-Math.PI / 2);
        cr.move_to (-y_ext.width / 2, 0);
        cr.show_text (y_title);
        cr.restore ();

        // Draw chart captions
        string caption_line1 = "Solar Elevation Angle - Date: %s".printf (selected_date.format ("%Y-%m-%d"));
        string caption_line2 = "Lat: %.2f°, Lon: %.2f°, TZ: UTC%+.2f".printf (latitude, longitude, timezone_offset_hours);
        
        cr.set_font_size (18);
        Cairo.TextExtents cap_ext1, cap_ext2;
        cr.text_extents (caption_line1, out cap_ext1);
        cr.text_extents (caption_line2, out cap_ext2);

        double total_caption_height = cap_ext1.height + cap_ext2.height + 5;

        cr.move_to ((width - cap_ext1.width) / 2, (MARGIN_TOP - total_caption_height) / 2 + cap_ext1.height);
        cr.show_text (caption_line1);
        cr.move_to ((width - cap_ext2.width) / 2, (MARGIN_TOP - total_caption_height) / 2 + cap_ext1.height + 5 + cap_ext2.height);
        cr.show_text (caption_line2);
    }

    /**
     * Handles export button click event.
     *
     * Shows a file save dialog with filters for PNG, SVG, and PDF formats.
     */
    private void on_export_clicked () {
        // Show save dialog with PNG, SVG, PDF filters
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
            initial_name = "solar_elevation_chart.png",
            filters = filter_list,
        };

        file_dialog.save.begin (window, null, (obj, res) => {
            try {
                var file = file_dialog.save.end (res);
                if (file != null) {
                    export_chart (file);
                }
            } catch (Error e) {
                // Dismissed by user, so do not show alert dialog
                message ("Image file has not been saved: %s", e.message);
            }
        });
    }

    /**
     * Exports the current chart to a file.
     *
     * Supports PNG, SVG, and PDF formats based on file extension.
     * Defaults to PNG if extension is not recognized.
     *
     * @param file The file to export the chart to.
     */
    private void export_chart (File file) {
        int width = drawing_area.get_width ();
        int height = drawing_area.get_height ();

        if (width <= 0 || height <= 0) {
            width = 800;
            height = 600;
        }

        string filepath = file.get_path ();
        string? extension = null;
        var last_dot = filepath.last_index_of_char ('.');
        if (last_dot != -1) {
            extension = filepath[last_dot:].down ();
        }

        if (extension == ".svg") {
            Cairo.SvgSurface surface = new Cairo.SvgSurface (filepath, width, height);
            Cairo.Context cr = new Cairo.Context (surface);
            draw_sun_angle_chart (drawing_area, cr, width, height);
        } else if (extension == ".pdf") {
            Cairo.PdfSurface surface = new Cairo.PdfSurface (filepath, width, height);
            Cairo.Context cr = new Cairo.Context (surface);
            draw_sun_angle_chart (drawing_area, cr, width, height);
        } else {
            Cairo.ImageSurface surface = new Cairo.ImageSurface (Cairo.Format.RGB24, width, height);
            Cairo.Context cr = new Cairo.Context (surface);
            draw_sun_angle_chart (drawing_area, cr, width, height);
            surface.write_to_png (filepath);
        }
    }

    /**
     * Handles CSV export button click event.
     *
     * Shows a file save dialog for CSV format.
     */
    private void on_export_csv_clicked () {
        var csv_filter = new Gtk.FileFilter ();
        csv_filter.name = "CSV Files";
        csv_filter.add_mime_type ("text/csv");

        var filter_list = new ListStore (typeof (Gtk.FileFilter));
        filter_list.append (csv_filter);

        var file_dialog = new Gtk.FileDialog () {
            modal = true,
            initial_name = "solar_elevation_data.csv",
            filters = filter_list,
        };

        file_dialog.save.begin (window, null, (obj, res) => {
            try {
                var file = file_dialog.save.end (res);
                if (file != null) {
                    export_csv_data (file);
                }
            } catch (Error e) {
                // Dismissed by user, so do not show alert dialog
                message ("CSV file has not been saved: %s", e.message);
            }
        });
    }

    /**
     * Exports the solar elevation data to a CSV file.
     *
     * @param file The file to export the data to.
     */
    private void export_csv_data (File file) {
        try {
            var stream = file.replace (null, false, FileCreateFlags.REPLACE_DESTINATION);
            var data_stream = new DataOutputStream (stream);

            // Write CSV metadata as comments
            data_stream.put_string ("# Solar Elevation Data\n");
            data_stream.put_string ("# Date: %s\n".printf (selected_date.format ("%Y-%m-%d")));
            data_stream.put_string ("# Latitude: %.2f degrees\n".printf (latitude));
            data_stream.put_string ("# Longitude: %.2f degrees\n".printf (longitude));
            data_stream.put_string ("# Timezone: UTC%+.2f\n".printf (timezone_offset_hours));
            data_stream.put_string ("#\n");

            // Write CSV header
            data_stream.put_string ("Time,Solar Elevation (degrees)\n");

            // Write data points
            for (int i = 0; i < RESOLUTION_PER_MIN; i += 1) {
                int hours = i / 60;
                int minutes = i % 60;
                data_stream.put_string (
                    "%02d:%02d,%.3f\n".printf (hours, minutes, sun_angles[i])
                );
            }

            data_stream.close ();
        } catch (Error e) {
            show_error_dialog ("CSV export failed", e.message);
        }
    }

    /**
     * Application entry point.
     *
     * Creates and runs the SolarAngleApp instance.
     *
     * @param args Command line arguments.
     * @return Exit code.
     */
    public static int main (string[] args) {
        var app = new SolarAngleApp ();
        return app.run (args);
    }
}
