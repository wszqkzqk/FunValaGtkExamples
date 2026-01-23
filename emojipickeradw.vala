#!/usr/bin/env -S vala --pkg=gtk4 --pkg=libadwaita-1 -X -lm -X -O2 -X -march=native -X -pipe
/* SPDX-License-Identifier: LGPL-2.1-or-later */

/**
 * Minimal Emoji Picker Application.
 *
 * A simple emoji picker that automatically copies selected emojis to clipboard.
 */
public class EmojiPickerApp : Adw.Application {
    private Adw.ApplicationWindow window;
    private Gtk.Button show_emoji_button;
    private Gtk.EmojiChooser emoji_chooser;

    /**
     * Creates a new EmojiPickerApp instance.
     */
    public EmojiPickerApp () {
        Object (application_id: "io.github.wszqkzqk.EmojiPicker");
    }

    /**
     * Activates the application and creates the main window.
     */
    protected override void activate () {
        window = new Adw.ApplicationWindow (this) {
            title = "Emoji Picker",
        };

        // Create header bar
        var header_bar = new Adw.HeaderBar () {
            title_widget = new Adw.WindowTitle ("Emoji Picker", ""),
        };

        // Create toolbar view
        var toolbar_view = new Adw.ToolbarView ();
        toolbar_view.add_top_bar (header_bar);

        // Create emoji chooser
        emoji_chooser = new Gtk.EmojiChooser ();
        emoji_chooser.emoji_picked.connect (on_emoji_picked);

        // Create main button to show emoji picker
        show_emoji_button = new Gtk.Button () {
            label = "📝 Click to Pick Emoji",
            margin_start = 24,
            margin_end = 24,
            margin_top = 24,
            margin_bottom = 24,
            vexpand = true,
            hexpand = true,
            css_classes = { "suggested-action", "pill" },
        };
        emoji_chooser.set_parent (show_emoji_button);
        show_emoji_button.clicked.connect (() => {
            emoji_chooser.popup ();
        });

        toolbar_view.content = show_emoji_button;
        window.content = toolbar_view;

        // Setup keyboard shortcuts
        setup_shortcuts ();

        window.present ();
        emoji_chooser.popup ();
    }

    /**
     * Sets up keyboard shortcuts for the application.
     */
    private void setup_shortcuts () {
        // Ctrl+Q to quit
        var quit_action = new SimpleAction ("quit", null);
        quit_action.activate.connect (() => {
            window.close ();
        });
        this.add_action (quit_action);
        this.set_accels_for_action ("app.quit", {"<Ctrl>q"});

        // Space or Enter to open emoji picker
        var open_action = new SimpleAction ("open", null);
        open_action.activate.connect (() => {
            emoji_chooser.popup ();
        });
        this.add_action (open_action);
        this.set_accels_for_action ("app.open", {"space", "Return"});
    }

    /**
     * Handles emoji selection and auto-copy to clipboard.
     */
    private void on_emoji_picked (string emoji) {
        // Auto-copy to clipboard
        var clipboard = window.get_clipboard ();
        clipboard.set_text (emoji);
        
        // Update button text to show copied emoji
        show_emoji_button.label = "%s Copied!".printf (emoji);
        
        // Reset button text after 0.1 second
        Timeout.add (100, () => {
            show_emoji_button.label += " Click to Pick Emoji";
            emoji_chooser.popup ();
            return Source.REMOVE;
        });
    }

    /**
     * Application entry point.
     */
    public static int main (string[] args) {
        var app = new EmojiPickerApp ();
        return app.run (args);
    }
}
