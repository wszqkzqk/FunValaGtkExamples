#!/usr/bin/env -S vala --pkg=gtk4 --pkg=libadwaita-1 -X -lm -X -O2 -X -march=native -X -pipe
/* SPDX-License-Identifier: LGPL-2.1-or-later */

/**
 * 2048 Game - libadwaita/Vala Implementation
 * Copyright (C) 2026 wszqkzqk <wszqkzqk@qq.com>
 *
 * A classic 2048 sliding puzzle game implemented with libadwaita and Vala.
 * Use arrow keys or WASD to move tiles and combine them to reach 2048!
 */

public class Game2048Adw : Adw.Application {
    private const int GRID_SIZE = 4;
    private const int TILE_SIZE = 80;
    private const int SPACING = 10;

    private Adw.ApplicationWindow window;
    private Gtk.Grid game_grid;
    private Gtk.Label score_label;
    private Gtk.Label best_score_label;
    private Gtk.Button new_game_button;
    private Gtk.Label[,] tile_labels;

    private int[,] board;
    private int score;
    private int best_score;
    private bool game_over;
    private bool won;

    construct {
        application_id = "io.github.wszqkzqk.Game2048Adw";
        best_score = 0; // In a real implementation, this would be loaded from settings
    }

    /**
     * Activates the application and creates the main window.
     */
    protected override void activate () {
        create_window ();
        init_game ();
        new_game ();
    }

    /**
     * Creates the main application window and UI elements.
     */
    private void create_window () {
        window = new Adw.ApplicationWindow (this) {
            title = "2048 Game",
            default_width = 400,
            default_height = 550,
            resizable = false,
        };

        var header_bar = new Adw.HeaderBar () {
            title_widget = new Adw.WindowTitle ("2048 Game", ""),
        };

        var toolbar_view = new Adw.ToolbarView ();
        toolbar_view.add_top_bar (header_bar);

        var main_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 20) {
            margin_start = 20,
            margin_end = 20,
            margin_top = 20,
            margin_bottom = 20,
        };

        // Title
        var title_label = new Gtk.Label ("2048") {
            css_classes = { "title-1" }
        };

        // Score area
        var score_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 15) {
            halign = Gtk.Align.CENTER
        };

        var score_frame = create_score_frame ("SCORE", out score_label);
        var best_score_frame = create_score_frame ("BEST", out best_score_label);

        score_box.append (score_frame);
        score_box.append (best_score_frame);

        // New game button
        new_game_button = new Gtk.Button.with_label ("New Game") {
            css_classes = { "suggested-action" }
        };
        new_game_button.clicked.connect (new_game);

        // Game instructions
        var instructions = new Gtk.Label (
            "Use arrow keys or WASD to move tiles.\nCombine tiles with the same number to reach 2048!"
        ) {
            justify = Gtk.Justification.CENTER,
            css_classes = { "caption" }
        };

        // Game grid container
        var grid_frame = new Gtk.Frame (null) {
            css_classes = { "game-board" }
        };

        game_grid = new Gtk.Grid () {
            row_spacing = SPACING,
            column_spacing = SPACING,
            halign = Gtk.Align.CENTER,
            valign = Gtk.Align.CENTER,
            margin_start = SPACING,
            margin_end = SPACING,
            margin_top = SPACING,
            margin_bottom = SPACING
        };

        grid_frame.child = game_grid;

        main_box.append (title_label);
        main_box.append (score_box);
        main_box.append (new_game_button);
        main_box.append (instructions);
        main_box.append (grid_frame);

        toolbar_view.content = main_box;

        // Setup keyboard controls
        var key_controller = new Gtk.EventControllerKey ();
        key_controller.key_pressed.connect (on_key_pressed);
        ((Gtk.Widget) window).add_controller (key_controller);

        // Add custom CSS
        add_custom_css ();

        window.content = toolbar_view;
        window.present ();
    }

    /**
     * Creates a score display frame.
     */
    private Gtk.Frame create_score_frame (string title, out Gtk.Label score_label) {
        var frame = new Gtk.Frame (null) {
            css_classes = { "score-frame" }
        };

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 5) {
            margin_start = 15,
            margin_end = 15,
            margin_top = 10,
            margin_bottom = 10
        };

        var title_label = new Gtk.Label (title) {
            css_classes = { "caption", "score-title" }
        };

        score_label = new Gtk.Label ("0") {
            css_classes = { "title-3", "score-value" }
        };

        box.append (title_label);
        box.append (score_label);
        frame.child = box;

        return frame;
    }

    /**
     * Initializes the game board and tile labels.
     */
    private void init_game () {
        board = new int[GRID_SIZE, GRID_SIZE];
        tile_labels = new Gtk.Label[GRID_SIZE, GRID_SIZE];

        // Create tile labels
        for (int row = 0; row < GRID_SIZE; row++) {
            for (int col = 0; col < GRID_SIZE; col++) {
                var label = new Gtk.Label ("") {
                    width_request = TILE_SIZE,
                    height_request = TILE_SIZE,
                    css_classes = { "tile" }
                };

                tile_labels[row, col] = label;
                game_grid.attach (label, col, row, 1, 1);
            }
        }
    }

    /**
     * Starts a new game.
     */
    private void new_game () {
        // Clear board
        for (int row = 0; row < GRID_SIZE; row++) {
            for (int col = 0; col < GRID_SIZE; col++) {
                board[row, col] = 0;
            }
        }

        score = 0;
        game_over = false;
        won = false;

        // Add two initial tiles
        add_random_tile ();
        add_random_tile ();

        update_display ();
    }

    /**
     * Adds a random tile (2 or 4) to an empty position.
     */
    private void add_random_tile () {
        var empty_cells = new GenericArray<int> ();

        // Find empty cells
        for (int row = 0; row < GRID_SIZE; row++) {
            for (int col = 0; col < GRID_SIZE; col++) {
                if (board[row, col] == 0) {
                    empty_cells.add (row * GRID_SIZE + col);
                }
            }
        }

        if (empty_cells.length == 0) return;

        // Choose random empty cell
        int random_index = Random.int_range (0, empty_cells.length);
        int cell = empty_cells[random_index];
        int row = cell / GRID_SIZE;
        int col = cell % GRID_SIZE;

        // Add 2 (90% chance) or 4 (10% chance)
        board[row, col] = Random.next_double () < 0.9 ? 2 : 4;
    }

    /**
     * Updates the visual display of the game.
     */
    private void update_display () {
        // Update tiles
        for (int row = 0; row < GRID_SIZE; row++) {
            for (int col = 0; col < GRID_SIZE; col++) {
                update_tile (row, col);
            }
        }

        // Update scores
        score_label.label = score.to_string ();
        if (score > best_score) {
            best_score = score;
        }
        best_score_label.label = best_score.to_string ();

        // Check game state
        check_game_state ();
    }

    /**
     * Updates a single tile's appearance.
     */
    private void update_tile (int row, int col) {
        var label = tile_labels[row, col];
        int value = board[row, col];

        if (value == 0) {
            label.label = "";
        } else {
            label.label = value.to_string ();
        }

        // Remove old value-specific style classes
        label.css_classes = { "tile" };

        // Add CSS class for this tile value
        if (value > 0) {
            label.add_css_class (@"tile-$(value)");
        }
    }

    /**
     * Handles key press events for game controls.
     */
    private bool on_key_pressed (uint keyval, uint keycode, Gdk.ModifierType state) {
        if (game_over) return false;

        bool moved = false;

        switch (keyval) {
            case Gdk.Key.Up:
            case Gdk.Key.w:
            case Gdk.Key.W:
                moved = move_up ();
                break;
            case Gdk.Key.Down:
            case Gdk.Key.s:
            case Gdk.Key.S:
                moved = move_down ();
                break;
            case Gdk.Key.Left:
            case Gdk.Key.a:
            case Gdk.Key.A:
                moved = move_left ();
                break;
            case Gdk.Key.Right:
            case Gdk.Key.d:
            case Gdk.Key.D:
                moved = move_right ();
                break;
            default:
                return false;
        }

        if (moved) {
            add_random_tile ();
            update_display ();
        }

        return true;
    }

    /**
     * Moves tiles up and combines them.
     */
    private bool move_up () {
        bool moved = false;

        for (int col = 0; col < GRID_SIZE; col++) {
            var column = new int[GRID_SIZE];
            int index = 0;

            // Collect non-zero values
            for (int row = 0; row < GRID_SIZE; row++) {
                if (board[row, col] != 0) {
                    column[index++] = board[row, col];
                }
            }

            // Combine adjacent equal values
            for (int i = 0; i < index - 1; i++) {
                if (column[i] == column[i + 1]) {
                    column[i] *= 2;
                    score += column[i];

                    // Shift remaining values
                    for (int j = i + 1; j < index - 1; j++) {
                        column[j] = column[j + 1];
                    }
                    column[--index] = 0;
                }
            }

            // Check if column changed
            for (int row = 0; row < GRID_SIZE; row++) {
                int new_value = row < index ? column[row] : 0;
                if (board[row, col] != new_value) {
                    moved = true;
                    board[row, col] = new_value;
                }
            }
        }

        return moved;
    }

    /**
     * Moves tiles down and combines them.
     */
    private bool move_down () {
        bool moved = false;

        for (int col = 0; col < GRID_SIZE; col++) {
            var column = new int[GRID_SIZE];
            int index = 0;

            // Collect non-zero values from bottom
            for (int row = GRID_SIZE - 1; row >= 0; row--) {
                if (board[row, col] != 0) {
                    column[index++] = board[row, col];
                }
            }

            // Combine adjacent equal values
            for (int i = 0; i < index - 1; i++) {
                if (column[i] == column[i + 1]) {
                    column[i] *= 2;
                    score += column[i];

                    // Shift remaining values
                    for (int j = i + 1; j < index - 1; j++) {
                        column[j] = column[j + 1];
                    }
                    column[--index] = 0;
                }
            }

            // Check if column changed
            for (int row = GRID_SIZE - 1; row >= 0; row--) {
                int new_value = (GRID_SIZE - 1 - row) < index ? column[GRID_SIZE - 1 - row] : 0;
                if (board[row, col] != new_value) {
                    moved = true;
                    board[row, col] = new_value;
                }
            }
        }

        return moved;
    }

    /**
     * Moves tiles left and combines them.
     */
    private bool move_left () {
        bool moved = false;

        for (int row = 0; row < GRID_SIZE; row++) {
            var row_values = new int[GRID_SIZE];
            int index = 0;

            // Collect non-zero values
            for (int col = 0; col < GRID_SIZE; col++) {
                if (board[row, col] != 0) {
                    row_values[index++] = board[row, col];
                }
            }

            // Combine adjacent equal values
            for (int i = 0; i < index - 1; i++) {
                if (row_values[i] == row_values[i + 1]) {
                    row_values[i] *= 2;
                    score += row_values[i];

                    // Shift remaining values
                    for (int j = i + 1; j < index - 1; j++) {
                        row_values[j] = row_values[j + 1];
                    }
                    row_values[--index] = 0;
                }
            }

            // Check if row changed
            for (int col = 0; col < GRID_SIZE; col++) {
                int new_value = col < index ? row_values[col] : 0;
                if (board[row, col] != new_value) {
                    moved = true;
                    board[row, col] = new_value;
                }
            }
        }

        return moved;
    }

    /**
     * Moves tiles right and combines them.
     */
    private bool move_right () {
        bool moved = false;

        for (int row = 0; row < GRID_SIZE; row++) {
            var row_values = new int[GRID_SIZE];
            int index = 0;

            // Collect non-zero values from right
            for (int col = GRID_SIZE - 1; col >= 0; col--) {
                if (board[row, col] != 0) {
                    row_values[index++] = board[row, col];
                }
            }

            // Combine adjacent equal values
            for (int i = 0; i < index - 1; i++) {
                if (row_values[i] == row_values[i + 1]) {
                    row_values[i] *= 2;
                    score += row_values[i];

                    // Shift remaining values
                    for (int j = i + 1; j < index - 1; j++) {
                        row_values[j] = row_values[j + 1];
                    }
                    row_values[--index] = 0;
                }
            }

            // Check if row changed
            for (int col = GRID_SIZE - 1; col >= 0; col--) {
                int new_value = (GRID_SIZE - 1 - col) < index ? row_values[GRID_SIZE - 1 - col] : 0;
                if (board[row, col] != new_value) {
                    moved = true;
                    board[row, col] = new_value;
                }
            }
        }

        return moved;
    }

    /**
     * Checks if the game is won or over.
     */
    private void check_game_state () {
        // Check for 2048 (win condition)
        if (!won) {
            for (int row = 0; row < GRID_SIZE; row++) {
                for (int col = 0; col < GRID_SIZE; col++) {
                    if (board[row, col] == 2048) {
                        won = true;
                        show_win_dialog ();
                        return;
                    }
                }
            }
        }

        // Check for game over
        if (is_board_full () && !has_possible_moves ()) {
            game_over = true;
            show_game_over_dialog ();
        }
    }

    /**
     * Checks if the board is full.
     */
    private bool is_board_full () {
        for (int row = 0; row < GRID_SIZE; row++) {
            for (int col = 0; col < GRID_SIZE; col++) {
                if (board[row, col] == 0) {
                    return false;
                }
            }
        }
        return true;
    }

    /**
     * Checks if there are any possible moves left.
     */
    private bool has_possible_moves () {
        // Check for adjacent equal values
        for (int row = 0; row < GRID_SIZE; row++) {
            for (int col = 0; col < GRID_SIZE; col++) {
                int value = board[row, col];

                // Check right neighbor
                if (col < GRID_SIZE - 1 && board[row, col + 1] == value) {
                    return true;
                }

                // Check bottom neighbor
                if (row < GRID_SIZE - 1 && board[row + 1, col] == value) {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * Shows the win dialog.
     */
    private void show_win_dialog () {
        var dialog = new Adw.AlertDialog (
            "Congratulations! You reached 2048!",
            @"Your score: $(score)\nKeep playing to get an even higher score!"
        );
        dialog.add_response ("continue", "Continue");
        dialog.add_response ("new_game", "New Game");
        dialog.default_response = "continue";

        dialog.choose.begin (window, null, (obj, res) => {
            var response = dialog.choose.end (res);
            if (response == "new_game") {
                new_game ();
            }
        });
    }

    /**
     * Shows the game over dialog.
     */
    private void show_game_over_dialog () {
        var dialog = new Adw.AlertDialog (
            "Game Over!",
            @"Your final score: $(score)\nTry again to beat your best score!"
        );
        dialog.add_response ("new_game", "New Game");
        dialog.add_response ("close", "Close");
        dialog.default_response = "new_game";

        dialog.choose.begin (window, null, (obj, res) => {
            var response = dialog.choose.end (res);
            if (response == "new_game") {
                new_game ();
            }
        });
    }

    /**
     * Adds custom CSS styling to the application.
     */
    private void add_custom_css () {
        var css_provider = new Gtk.CssProvider ();

        string css = """
            .game-board {
                background-color: #bbada0;
                border-radius: 10px;
            }

            .tile {
                border-radius: 6px;
                font-size: 24px;
                font-weight: bold;
                background-color: #cdc1b4;
                color: #776e65;
                border: none;
            }

            .tile-2 { background-color: #eee4da; color: #776e65; }
            .tile-4 { background-color: #ede0c8; color: #776e65; }
            .tile-8 { background-color: #f2b179; color: #f9f6f2; }
            .tile-16 { background-color: #f59563; color: #f9f6f2; }
            .tile-32 { background-color: #f67c5f; color: #f9f6f2; }
            .tile-64 { background-color: #f65e3b; color: #f9f6f2; }
            .tile-128 { background-color: #edcf72; color: #f9f6f2; }
            .tile-256 { background-color: #edcc61; color: #f9f6f2; }
            .tile-512 { background-color: #edc850; color: #f9f6f2; }
            .tile-1024 { background-color: #edc53f; color: #f9f6f2; font-size: 20px; }
            .tile-2048 { background-color: #edc22e; color: #f9f6f2; font-size: 20px; }
            .tile-4096 { background-color: #3c3a32; color: #f9f6f2; font-size: 18px; }
            .tile-8192 { background-color: #3c3a32; color: #f9f6f2; font-size: 18px; }

            .score-frame {
                background-color: #bbada0;
                border-radius: 6px;
                border: none;
            }

            .score-title {
                color: #eee4da;
                font-weight: bold;
            }

            .score-value {
                color: white;
                font-weight: bold;
            }
        """;

        css_provider.load_from_string (css);
        Gtk.StyleContext.add_provider_for_display (
            Gdk.Display.get_default (),
            css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
    }

    /**
     * Application entry point.
     */
    public static int main (string[] args) {
        var app = new Game2048Adw ();
        return app.run (args);
    }
}
