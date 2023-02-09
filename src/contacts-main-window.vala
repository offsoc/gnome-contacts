/*
 * Copyright (C) 2011 Alexander Larsson <alexl@redhat.com>
 * Copyright (C) 2021 Niels De Graef <nielsdegraef@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

using Folks;

[GtkTemplate (ui = "/org/gnome/Contacts/ui/contacts-main-window.ui")]
public class Contacts.MainWindow : Adw.ApplicationWindow {

  private const GLib.ActionEntry[] ACTION_ENTRIES = {
    { "new-contact", new_contact },
    { "edit-contact", edit_contact },
    { "edit-contact-cancel", edit_contact_cancel },
    { "edit-contact-save", edit_contact_save },
    { "focus-search", focus_search },
    { "mark-favorite", mark_favorite },
    { "unmark-favorite", unmark_favorite },
    { "link-marked-contacts", link_marked_contacts },
    { "delete-marked-contacts", delete_marked_contacts },
    { "export-marked-contacts", export_marked_contacts },
    { "show-contact-qr-code", show_contact_qr_code },
    { "unlink-contact", unlink_contact },
    { "delete-contact", delete_contact },
    { "sort-on", null, "s", "'surname'", sort_on_changed },
    { "undo-operation", undo_operation_action, "s" },
    { "cancel-operation", cancel_operation_action, "s" },
  };

  [GtkChild]
  private unowned Adw.NavigationSplitView content_box;
  [GtkChild]
  private unowned Gtk.Stack list_pane_stack;
  [GtkChild]
  private unowned Gtk.Overlay contact_pane_container;
  [GtkChild]
  private unowned Adw.NavigationPage list_pane_page;
  [GtkChild]
  private unowned Gtk.Widget list_pane;
  [GtkChild]
  public unowned Gtk.SearchEntry filter_entry;
  [GtkChild]
  private unowned Adw.Bin contacts_list_container;
  private unowned ContactList contacts_list;

  [GtkChild]
  private unowned Adw.NavigationPage contact_pane_page;
  private ContactPane contact_pane;
  [GtkChild]
  private unowned Adw.HeaderBar right_header;
  [GtkChild]
  private unowned Adw.ToastOverlay toast_overlay;
  [GtkChild]
  private unowned Gtk.Button select_cancel_button;
  [GtkChild]
  private unowned Gtk.MenuButton primary_menu_button;
  [GtkChild]
  private unowned Gtk.Box contact_sheet_buttons;
  [GtkChild]
  private unowned Gtk.Button add_button;
  [GtkChild]
  private unowned Gtk.Button cancel_button;
  [GtkChild]
  private unowned Gtk.Button done_button;
  [GtkChild]
  private unowned Gtk.Button selection_button;

  [GtkChild]
  private unowned Gtk.Revealer actions_bar;

  public UiState state { get; set; default = UiState.NORMAL; }

  // Window state
  public int window_width { get; set; }
  public int window_height { get; set; }

  public Settings settings { get; construct set; }

  public Store store { get; construct set; }

  public Contacts.OperationList operations { get; construct set; }

  // A separate SelectionModel for all marked contacts
  private Gtk.MultiSelection marked_contacts;

  construct {
    add_action_entries (ACTION_ENTRIES, this);

    this.store.selection.notify["selected-item"].connect (on_selection_changed);

    this.marked_contacts = new Gtk.MultiSelection (this.store.filter_model);
    this.marked_contacts.selection_changed.connect (on_marked_contacts_changed);
    this.marked_contacts.unselect_all (); // Call here to sync actions

    this.filter_entry.set_key_capture_widget (this);

    this.notify["state"].connect (on_ui_state_changed);

    this.create_list_pane ();
    this.create_contact_pane ();
    this.connect_button_signals ();
    this.restore_window_state ();

    if (Config.PROFILE == "development")
        this.add_css_class ("devel");
  }

  public MainWindow (Settings settings,
                     OperationList operations,
                     App app,
                     Store contacts_store) {
    Object (
      application: app,
      operations: operations,
      settings: settings,
      store: contacts_store
    );

    unowned var sort_key = this.settings.sort_on_surname? "surname" : "firstname";
    var sort_action = (SimpleAction) this.lookup_action ("sort-on");
    sort_action.set_state (new Variant.string (sort_key));
  }

  private void restore_window_state () {
    // Apply them
    if (this.settings.window_width > 0 && this.settings.window_height > 0)
      set_default_size (this.settings.window_width, this.settings.window_height);
    this.maximized = this.settings.window_maximized;
    this.fullscreened = this.settings.window_fullscreen;
  }

  private void create_list_pane () {
    var contactslist = new ContactList (this.store, this.marked_contacts);
    bind_property ("state", contactslist, "state", BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
    this.contacts_list = contactslist;
    this.contacts_list_container.set_child (contactslist);
  }

  private void create_contact_pane () {
    this.contact_pane = new ContactPane (this, this.store);
    this.contact_pane.visible = true;
    this.contact_pane.hexpand = true;
    this.contact_pane.contacts_linked.connect (contact_pane_contacts_linked_cb);
    this.contact_pane_container.set_child (this.contact_pane);
  }

  /**
   * This shows the contact list on the left. This needs to be called
   * explicitly when contacts are loaded, as the original setup will
   * only show a loading spinner.
   */
  public void show_contact_list () {
    // FIXME: if no contact is loaded per backend, I must place a sign
    // saying "import your contacts/add online account"
    this.list_pane_stack.visible_child = this.list_pane;
  }

  private void on_marked_contacts_changed (Gtk.SelectionModel marked,
                                           uint position,
                                           uint n_changed) {
    var n_selected = marked.get_selection ().get_size ();

    // Update related actions
    unowned var action = lookup_action ("delete-marked-contacts");
    ((SimpleAction) action).set_enabled (n_selected > 0);

    action = lookup_action ("export-marked-contacts");
    ((SimpleAction) action).set_enabled (n_selected > 0);

    action = lookup_action ("link-marked-contacts");
    ((SimpleAction) action).set_enabled (n_selected > 1);

    string left_title = _("Contacts");
    if (this.state == UiState.SELECTING) {
      left_title = ngettext ("%llu Selected", "%llu Selected", (ulong) n_selected)
                                   .printf (n_selected);
    }
    this.list_pane_page.title = left_title;
  }

  private void on_ui_state_changed (Object obj, ParamSpec pspec) {
    // UI when we're not editing of selecting stuff
    this.add_button.visible
        = this.primary_menu_button.visible
        = (this.state == UiState.NORMAL || this.state == UiState.SHOWING);

    // UI when showing a contact
    this.contact_sheet_buttons.visible
      = (this.state == UiState.SHOWING);

    // Selecting UI
    this.select_cancel_button.visible = (this.state == UiState.SELECTING);
    this.selection_button.visible = !(this.state == UiState.SELECTING || this.state.editing ());

    if (this.state != UiState.SELECTING)
      this.list_pane_page.title = _("Contacts");

    // Editing UI
    this.cancel_button.visible
        = this.done_button.visible
        = this.right_header.show_end_title_buttons
        = this.state.editing ();
    this.right_header.show_end_title_buttons = !this.state.editing ();
    if (this.state.editing ()) {
      this.done_button.label = (this.state == UiState.CREATING)? _("_Add") : _("Done");
      // Cast is required because Gtk.Button.set_focus_on_click is deprecated and
      // we have to use Gtk.Widget.set_focus_on_click instead
      this.done_button.set_focus_on_click (true);
    }

    // Allow the back gesture when not browsing
    this.contact_pane_page.can_pop = this.state == UiState.NORMAL ||
                                     this.state == UiState.SHOWING ||
                                     this.state == UiState.SELECTING;

    this.content_box.show_content = this.state == UiState.SHOWING ||
                                    this.state.editing ();

    // Disable when editing a contact
    this.filter_entry.sensitive
        = this.contacts_list.sensitive
        = !this.state.editing ();

    this.actions_bar.reveal_child = (this.state == UiState.SELECTING);
  }

  private void edit_contact (GLib.SimpleAction action, GLib.Variant? parameter) {
    unowned var selected = this.store.get_selected_contact ();
    return_if_fail (selected != null);

    this.state = UiState.UPDATING;

    var title = _("Editing %s").printf (selected.display_name);
    this.contact_pane_page.title = title;
    this.contact_pane.edit_contact ();
  }

  private void show_contact_qr_code (GLib.SimpleAction action, GLib.Variant? parameter) {
    unowned var selected = this.store.get_selected_contact ();
    var dialog = new QrCodeDialog.for_contact (selected, get_root () as Gtk.Window);
    dialog.show ();
  }

  private void update_favorite_actions (bool favorite) {
    var mark_action = (SimpleAction) lookup_action ("mark-favorite");
    var unmark_action = (SimpleAction) lookup_action ("unmark-favorite");

    mark_action.set_enabled (!favorite);
    unmark_action.set_enabled (favorite);
  }

  private void set_selection_is_favorite (bool favorite) {
    unowned var selected = this.store.get_selected_contact ();
    return_if_fail (selected != null);

    selected.is_favourite = favorite;

    update_favorite_actions (favorite);
  }

  private void mark_favorite (GLib.SimpleAction action, GLib.Variant? parameter) {
    set_selection_is_favorite (true);
  }

  private void unmark_favorite (GLib.SimpleAction action, GLib.Variant? parameter) {
    set_selection_is_favorite (false);
  }

  [GtkCallback]
  private void on_selection_button_clicked () {
    this.state = UiState.SELECTING;
    var left_title = ngettext ("%d Selected", "%d Selected", 0) .printf (0);
    this.list_pane_page.title = left_title;
  }

  private void unlink_contact (GLib.SimpleAction action, GLib.Variant? parameter) {
    unowned Individual? selected = this.store.get_selected_contact ();
    return_if_fail (selected != null);

    this.store.selection.unselect_item (this.store.selection.get_selected ());
    this.state = UiState.NORMAL;

    var operation = new UnlinkOperation (this.store, selected);
    this.operations.execute.begin (operation, null, (obj, res) => {
      try {
        this.operations.execute.end (res);
      } catch (GLib.Error e) {
        warning ("Error unlinking individuals: %s", e.message);
      }
    });

    add_toast_for_operation (operation, "win.undo-operation", _("_Undo"));
  }

  private void delete_contact (GLib.SimpleAction action, GLib.Variant? parameter) {
    var selection = this.store.selection.get_selection ().copy ();
    if (selection.is_empty ())
      return;

    this.contacts_list.set_contacts_visible (selection, false);
    this.contact_pane.show_contact (null);
    delete_contacts (selection);
  }

  private void sort_on_changed (SimpleAction action, GLib.Variant? new_state) {
    unowned var sort_key = new_state.get_string ();
    this.settings.sort_on_surname = (sort_key == "surname");
    action.set_state (new_state);
  }

  private void undo_operation_action (SimpleAction action, GLib.Variant? parameter) {
    unowned var uuid = parameter.get_string ();
    this.operations.undo_operation.begin (uuid, (obj, res) => {
      try {
        this.operations.undo_operation.end (res);
      } catch (GLib.Error e) {
        warning ("Couldn't undo operation '%s': %s", uuid, e.message);
      }
    });
  }

  private void cancel_operation_action (SimpleAction action, GLib.Variant? parameter) {
    unowned var uuid = parameter.get_string ();
    this.operations.cancel_operation.begin (uuid, (obj, res) => {
      try {
        this.operations.cancel_operation.end (res);
      } catch (GLib.Error e) {
        warning ("Couldn't cancel operation '%s': %s", uuid, e.message);
      }
    });
  }

  private void edit_contact_save (SimpleAction action, GLib.Variant? parameter) {
    if (this.state != UiState.CREATING && this.state != UiState.UPDATING)
      return;

    if (this.state == UiState.CREATING) {
      this.state = UiState.NORMAL;
    } else {
      this.state = UiState.SHOWING;
    }
    this.contact_pane.stop_editing (false);
    this.contacts_list.scroll_to_selected ();

    this.contact_pane_page.title = "";
  }

  private void edit_contact_cancel (SimpleAction action, GLib.Variant? parameter) {
    if (this.state != UiState.CREATING && this.state != UiState.UPDATING)
      return;

    if (this.state == UiState.CREATING) {
      this.state = UiState.NORMAL;
    } else {
      this.state = UiState.SHOWING;
    }
    this.contact_pane.stop_editing (true);
    this.contacts_list.scroll_to_selected ();

    this.contact_pane_page.title = "";
  }

  private void focus_search (SimpleAction action, GLib.Variant? parameter) {
    this.filter_entry.grab_focus ();
  }

  public void new_contact (GLib.SimpleAction action, GLib.Variant? parameter) {
    if (this.state == UiState.UPDATING || this.state == UiState.CREATING)
      return;

    this.store.selection.unselect_item (this.store.selection.get_selected ());

    this.state = UiState.CREATING;

    this.contact_pane_page.title = _("New Contact");

    this.contact_pane.new_contact ();
    this.content_box.show_content = true;
  }

  [GtkCallback]
  private void on_collapsed () {
    // If we're not showing a contact or in selection mode, we want to show the
    // sidebar on fold
    var show_content = this.state != UiState.NORMAL &&
                       this.state != UiState.SELECTING;
    this.content_box.show_content = show_content;
  }

  [GtkCallback]
  private void on_show_content () {
    if (this.content_box.collapsed &&
        !this.content_box.show_content)
      this.store.selection.unselect_item (this.store.selection.get_selected ());
  }

  public void show_search (string query) {
    this.filter_entry.set_text (query);
  }

  private void connect_button_signals () {
    this.select_cancel_button.clicked.connect (() => {
        this.marked_contacts.unselect_all ();
        if (this.store.selection.get_selected () != Gtk.INVALID_LIST_POSITION) {
            this.state = UiState.SHOWING;
        } else {
            this.state = UiState.NORMAL;
        }
    });
  }

  public override bool close_request () {
    // Clear the contacts so any changed information is stored
    this.contact_pane.show_contact (null);

    this.settings.window_width = this.default_width;
    this.settings.window_height = this.default_height;
    this.settings.window_maximized = this.maximized;
    this.settings.window_fullscreen = this.fullscreened;

    return base.close_request ();
  }

  private void on_selection_changed (Object object, ParamSpec pspec) {
    unowned var selected = this.store.get_selected_contact ();

    // Update related actions
    unowned var unlink_action = lookup_action ("unlink-contact");
    ((SimpleAction) unlink_action).set_enabled (selected != null && selected.personas.size > 1);

    // We really want to treat selection mode specially
    if (this.state != UiState.SELECTING) {
      // FIXME: ask the user to leave edit-mode and act accordingly
      if (this.contact_pane.on_edit_mode)
        activate_action ("stop-editing-contact", new Variant.boolean (false));

      this.contact_pane.show_contact (selected);
      if (selected != null)
        this.content_box.show_content = true;

      // clearing right_header
      this.contact_pane_page.title = "";
      if (selected != null) {
        update_favorite_actions (selected.is_favourite);
      }
      this.state = selected != null ? UiState.SHOWING : UiState.NORMAL;
    }
  }

  private void link_marked_contacts (GLib.SimpleAction action, GLib.Variant? parameter) {
    // Take a copy, since we'll unselect everything later
    var selection = this.marked_contacts.get_selection ().copy ();

    // Go back to normal state as much as possible, and hide the contacts that
    // will be linked together
    this.store.selection.unselect_item (this.store.selection.get_selected ());
    this.marked_contacts.unselect_all ();
    this.contacts_list.set_contacts_visible (selection, false);
    this.contact_pane.show_contact (null);
    this.state = UiState.NORMAL;

    // Build the list of contacts
    var list = bitset_to_individuals (this.marked_contacts,
                                      selection);

    // Perform the operation
    var operation = new LinkOperation (this.store, list);
    this.operations.execute.begin (operation, null, (obj, res) => {
      try {
        this.operations.execute.end (res);
      } catch (GLib.Error e) {
        warning ("Error linking individuals: %s", e.message);
      }
    });

    add_toast_for_operation (operation, "win.undo-operation", _("_Undo"));
  }

  private void delete_marked_contacts (GLib.SimpleAction action, GLib.Variant? parameter) {
    var selection = this.marked_contacts.get_selection ().copy ();
    delete_contacts (selection);
  }

  private void delete_contacts (Gtk.Bitset selection) {
    // Go back to normal state as much as possible, and hide the contacts that
    // will be deleted
    this.store.selection.unselect_item (this.store.selection.get_selected ());
    this.marked_contacts.unselect_all ();
    this.contacts_list.set_contacts_visible (selection, false);
    this.contact_pane.show_contact (null);
    this.state = UiState.NORMAL;

    var individuals = bitset_to_individuals (this.store.filter_model,
                                             selection);

    // NOTE: we'll do this with a timeout, since the operation is not reversable
    var op = new DeleteOperation (individuals);

    var cancellable = new Cancellable ();
    cancellable.cancelled.connect ((c) => {
      this.contacts_list.set_contacts_visible (selection, true);
    });

    var toast = add_toast_for_operation (op, "win.cancel-operation", _("_Cancel"));
    this.operations.execute_with_timeout.begin (op, toast.timeout, cancellable, (obj, res) => {
      try {
        this.operations.execute_with_timeout.end (res);
      } catch (GLib.Error e) {
        warning ("Error removing individuals: %s", e.message);
      }
    });
  }

  private void contact_pane_contacts_linked_cb (LinkOperation operation) {
    add_toast_for_operation (operation, "win.undo-operation", _("_Undo"));

    this.operations.execute.begin (operation, null, (obj, res) => {
      try {
        this.operations.execute.end (res);
      } catch (GLib.Error e) {
        warning ("Error linking individuals: %s", e.message);
      }
    });
  }

  private Adw.Toast add_toast_for_operation (Operation operation,
                                             string? action_name = null,
                                             string? action_label = null) {
    var toast = new Adw.Toast (operation.description);
    if (action_name != null) {
      toast.set_button_label (action_label);
      toast.action_name = action_name;
      toast.action_target = operation.uuid;
    }
    this.toast_overlay.add_toast (toast);
    return toast;
  }

  private void export_marked_contacts (GLib.SimpleAction action, GLib.Variant? parameter) {
    // Take a copy, since we'll unselect everything later
    var selection = this.marked_contacts.get_selection ().copy ();

    // Go back to normal state as much as possible
    this.store.selection.unselect_item (this.store.selection.get_selected ());
    this.marked_contacts.unselect_all ();
    this.state = UiState.NORMAL;

    var individuals = bitset_to_individuals (this.store.filter_model,
                                             selection);
    export_individuals (individuals);
  }


  public void export_individuals (Gee.List<Individual> individuals) {
    // Open up a file chooser
    var file_dialog = new Gtk.FileDialog ();
    file_dialog.title = _("Export to file");
    file_dialog.accept_label = _("_Export");
    file_dialog.set_initial_name (_("contacts.vcf"));
    file_dialog.modal = true;
    file_dialog.save.begin (this, null, (obj, response) => {
      try {
        var file = file_dialog.save.end (response);

        // Do the actual export
        OutputStream filestream = null;
        try {
          filestream = file.replace (null, false, FileCreateFlags.NONE);
        } catch (Error err) {
          warning ("Couldn't create file: %s", err.message);
          return;
        }

        var op = new Io.VCardExportOperation (individuals, filestream);
        this.operations.execute.begin (op, null, (obj, res) => {
          try {
            this.operations.execute.end (res);
            filestream.close ();
          } catch (Error e) {
            warning ("ERROR: %s", e.message);
          }
        });

        add_toast_for_operation (op);
      } catch (Error error) {
        switch (error.code) {
          case Gtk.DialogError.CANCELLED:
          case Gtk.DialogError.DISMISSED:
            debug ("Dismissed opening file: %s", error.message);
            break;
          case Gtk.DialogError.FAILED:
          default:
            warning ("Could not open file: %s", error.message);
            break;
        }
      }
    });
  }

  // Little helper
  private Gee.LinkedList<Individual> bitset_to_individuals (GLib.ListModel model,
                                                            Gtk.Bitset bitset) {
    var list = new Gee.LinkedList<Individual> ();

    var iter = Gtk.BitsetIter ();
    uint index;
    if (!iter.init_first (bitset, out index))
      return list;

    do {
      list.add ((Individual) model.get_item (index));
    } while (iter.next (out index));

    return list;
  }

  [GtkCallback]
  private void filter_entry_changed (Gtk.Editable editable) {
    unowned var query = this.store.filter.query as SimpleQuery;
    query.query_string = this.filter_entry.text;
  }
}
