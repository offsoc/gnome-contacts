/*
 * Copyright (C) 2022 Niels De Graef <nielsdegraef@gmail.com>
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

/**
 * A customer sorter that sorts {@link Chunk}s so that personas are grouped.
 */
public class Contacts.ChunkSorter : Gtk.Sorter {

  private PersonaSorter persona_sorter = new PersonaSorter ();

  private const string[] SORTED_PROPERTIES = {
    "email-addresses",
    "phone-numbers",
    "im-addresses",
    "roles",
    "urls",
    "nickname",
    "birthday",
    "postal-addresses",
    "notes"
  };

  public override Gtk.SorterOrder get_order () {
    return Gtk.SorterOrder.PARTIAL;
  }

  public override Gtk.Ordering compare (Object? item1, Object? item2) {
    unowned var chunk_1 = (Chunk) item1;
    unowned var chunk_2 = (Chunk) item2;

    // Put null persona's last
    if ((chunk_1.persona == null) != (chunk_2.persona == null))
      return (chunk_1.persona == null)? Gtk.Ordering.LARGER : Gtk.Ordering.SMALLER;

    if (chunk_1.persona != null) {
      var persona_order = this.persona_sorter.compare (chunk_1.persona,
                                                       chunk_2.persona);
      if (persona_order != Gtk.Ordering.EQUAL)
        return persona_order;
    }

    // We have 2 equal persona's (or 2 times null).
    // Either way, we can then sort on property name
    var index_1 = prop_index (chunk_1.property_name);
    var index_2 = prop_index (chunk_2.property_name);
    return Gtk.Ordering.from_cmpfunc (index_1 - index_2);
  }

  private int prop_index (string property_name) {
    for (int i = 0; i < SORTED_PROPERTIES.length; i++) {
      if (property_name == SORTED_PROPERTIES[i])
        return i;
    }

    return -1;
  }
}
