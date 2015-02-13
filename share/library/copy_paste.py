""" This plug-in provides various menus, contextual or not, to cut, copy and
paste text.

In particular, it also provide the capability to copy some text with the
corresponding line numbers. For example, if you select a whole buffer that
contains

procedure Void is
begin
   null;
end Void;

and activate the /Edit/Copy with line numbers menu, the following entry will
be added to the clipboard:

1. procedure Void is
2. begin
3.    null;
4. end Void;

Note that line numbers will be aligned to the biggest one, e.g.

 8. procedure Two is
 9. begin
10.    null;
11. end Two;

"""

###########################################################################
# No user customization below this line
############################################################################

import GPS
import gps_utils

GPS.Preference("Plugins/copy paste/stdmenu").create(
    "Contextual menu", "boolean",
    """If enabled, contextual menus will be created for copying, cutting
and pasting text.
They will correspond to the /Edit/Copy, /Edit/Cut and /Edit/Paste menus.
You must restart GPS to take changes into account.""",
    True)

GPS.Preference("Plugins/copy paste/greyedout").create(
    "Grey out contextual menu", "boolean",
    """If disabled, contextual menu entries are hidden when not applicable.
If enabled, the entries are still visible by greyed out.
You must restart GPS to take changes into account.""",
    True)

GPS.Preference("Plugins/copy paste/copy_with_line_nums").create(
    "Copy with line numbers", "boolean",
    """If enabled and Contextual Menu is also enabled, a contextual menu to
copy some text with the line numbers will be created.
Otherwise, the capability will only be accessible from the /Edit/Copy with
line numbers menu and possibly the associated key shortcut.""",
    False)


def copy_with_line_numbers(menu):
    buffer = GPS.EditorBuffer.get()
    loc_start = buffer.selection_start()
    loc_end = buffer.selection_end().forward_char(-1)
    selection_start = loc_start.line()
    selection_end = loc_end.line()
    result = ""

    max_len = len('%s' % selection_end)

    for line in range(selection_start, selection_end + 1):
        if line == selection_end:
            end = loc_end
        else:
            end = loc_start.end_of_line()

        prefix = ""
        for j in range(len('%s' % line), max_len):
            prefix = prefix + " "

        result = result + '%s%s. %s' % (
            prefix, line, buffer.get_chars(loc_start, end))
        loc_start = loc_start.forward_line(1)

    GPS.Clipboard.copy(result)


def on_area(context):
    buf = GPS.EditorBuffer.get(open=False)
    if not buf:
        return False

    start = buf.selection_start()
    end = buf.selection_end()
    return start != end


def on_source_editor_area(context):
    global grey_out_contextual
    return gps_utils.in_editor(context) and \
        (grey_out_contextual or on_area(context))


def on_copy(context):
    GPS.Editor.copy()


def on_cut(context):
    GPS.Editor.cut()


def on_paste(context):
    GPS.Editor.paste()


def on_gps_started(hook):
    global grey_out_contextual

    GPS.Menu.create(
        "/Edit/Copy with line numbers",
        on_activate=copy_with_line_numbers,
        ref="Copy",
        add_before=False)

    if GPS.Preference("Plugins/copy paste/stdmenu").get():
        grey_out_contextual = GPS.Preference(
            "Plugins/copy paste/greyedout").get()

        GPS.Contextual("Cut in editor").create(
            on_activate=on_cut,
            filter=on_source_editor_area,
            group=-1,
            visibility_filter=on_area,
            label=lambda x: "Cut")
        GPS.Contextual("Copy in editor").create(
            on_activate=on_copy,
            filter=on_source_editor_area,
            group=-1,
            visibility_filter=on_area,
            label=lambda x: "Copy",
            ref="Cut in editor",
            add_before=False)
        GPS.Contextual("Paste in editor").create(
            on_activate=on_paste,
            group=-1,
            filter=gps_utils.in_editor,
            label=lambda x: "Paste",
            ref="Copy in editor",
            add_before=False)

        if GPS.Preference("Plugins/copy paste/copy_with_line_nums").get():
            GPS.Contextual("Copy with line numbers").create(
                on_activate=copy_with_line_numbers,
                filter=on_source_editor_area,
                group=-1,
                visibility_filter=on_area,
                ref="Cut in editor")

        GPS.Contextual("sep_group_in_editor").create(
            on_activate=None,
            group=-1,
            filter=gps_utils.in_editor,
            ref="Paste in editor",
            add_before=False)

GPS.Hook("gps_started").add(on_gps_started)
