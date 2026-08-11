import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(fileURLToPath(new URL("..", import.meta.url)));
const nativeSdkRoot = resolve(repositoryRoot, "node_modules/@native-sdk/cli");
const packageJsonPath = resolve(nativeSdkRoot, "package.json");
const viewPath = resolve(nativeSdkRoot, "src/runtime/view.zig");
const viewTreePath = resolve(nativeSdkRoot, "src/runtime/view_widget_tree.zig");
const eventsPath = resolve(nativeSdkRoot, "src/runtime/canvas_widget_events.zig");
const gpuSurfaceEventsPath = resolve(nativeSdkRoot, "src/runtime/gpu_surface_events.zig");
const contextMenuPath = resolve(nativeSdkRoot, "src/runtime/canvas_widget_context_menu.zig");
const runtimeApiPath = resolve(nativeSdkRoot, "src/runtime/api.zig");
const uiAppPath = resolve(nativeSdkRoot, "src/runtime/ui_app.zig");
const uiAppTestsPath = resolve(nativeSdkRoot, "src/runtime/ui_app_tests.zig");
const anchoredTestsPath = resolve(
  nativeSdkRoot,
  "src/runtime/canvas_widget_anchored_tests.zig",
);
const uiPath = resolve(nativeSdkRoot, "src/primitives/canvas/ui.zig");
const schemaPath = resolve(nativeSdkRoot, "src/primitives/canvas/ui_schema.zig");
const markupPath = resolve(nativeSdkRoot, "src/primitives/canvas/ui_markup.zig");
const markupContractPath = resolve(
  nativeSdkRoot,
  "src/primitives/canvas/ui_markup_contract.zig",
);
const markupCompiledPath = resolve(
  nativeSdkRoot,
  "src/primitives/canvas/ui_markup_compiled.zig",
);
const markupViewPath = resolve(
  nativeSdkRoot,
  "src/primitives/canvas/ui_markup_view.zig",
);
const textInputPath = resolve(
  nativeSdkRoot,
  "src/primitives/canvas/widget_text_input.zig",
);
const canvasEventsPrimitivePath = resolve(
  nativeSdkRoot,
  "src/primitives/canvas/events.zig",
);
const controlRenderPath = resolve(
  nativeSdkRoot,
  "src/primitives/canvas/widget_render_controls.zig",
);

const nativeSdk = JSON.parse(readFileSync(packageJsonPath, "utf8"));
if (nativeSdk.version !== "0.6.1") {
  throw new Error(
    `The combobox Tab patch is written for @native-sdk/cli 0.6.1, found ${nativeSdk.version}.`,
  );
}

function replaceOnce(source, expected, replacement, description) {
  if (!source.includes(expected)) {
    throw new Error(`Unable to apply Native SDK combobox patch: ${description}.`);
  }
  return source.replace(expected, replacement);
}

let schema = readFileSync(schemaPath, "utf8");
if (!schema.includes('.name = "blur", .dead_on_non_hit_target = true')) {
  const anchor = '    .{ .code = 5, .name = "input", .payload = .text_input, .dead_on_non_hit_target = true },\n';
  const replacement = `${anchor}    // Text-entry focus moved to another canvas target through pointer or keyboard navigation.\n    .{ .code = 14, .name = "blur", .dead_on_non_hit_target = true },\n`;
  schema = replaceOnce(schema, anchor, replacement, "blur schema anchor changed");
  writeFileSync(schemaPath, schema);
}

let markup = readFileSync(markupPath, "utf8");
if (!markup.includes("pub fn blurEventElement")) {
  const helperAnchor = 'pub const autofocus_element_message = "autofocus is only supported on focusable controls (text fields, buttons, checkboxes, ...) - it moves keyboard focus to the element when it mounts or when the flag turns on, and nothing about this element can take focus";\n';
  const helper = `/// The user-focus blur event is deliberately text-entry-only. Buttons and\n/// list rows can move focus, but their primary semantics are press/select, not\n/// field commit; accepting on-blur there would create a dead or surprising Msg.\npub fn blurEventElement(name: []const u8) bool {\n    return std.mem.eql(u8, name, "input") or\n        std.mem.eql(u8, name, "text-field") or\n        std.mem.eql(u8, name, "search-field") or\n        std.mem.eql(u8, name, "combobox") or\n        std.mem.eql(u8, name, "textarea");\n}\n\npub const on_blur_element_message = "on-blur is only supported on text-entry controls (input, text-field, search-field, combobox, textarea) - it dispatches when keyboard focus moves away through a pointer or keyboard focus transition";\n\n`;
  markup = replaceOnce(markup, helperAnchor, `${helper}${helperAnchor}`, "blur markup helper anchor changed");

  const validationAnchor = `                    } else if (std.mem.eql(u8, attribute.name, "on-resize")) {\n                        // The runtime emits fraction changes for split\n                        // dividers only; anywhere else the handler could\n                        // never fire.\n                        if (!std.mem.eql(u8, node.name, "split")) {\n                            return attrError(node, attribute, on_resize_element_message);\n                        }\n                    } else if (nameInList(node.name, &known_non_hit_target_element_names) and deadHandlerOnNonHitTarget(attribute.name)) {`;
  const validationReplacement = `                    } else if (std.mem.eql(u8, attribute.name, "on-resize")) {\n                        // The runtime emits fraction changes for split\n                        // dividers only; anywhere else the handler could\n                        // never fire.\n                        if (!std.mem.eql(u8, node.name, "split")) {\n                            return attrError(node, attribute, on_resize_element_message);\n                        }\n                    } else if (std.mem.eql(u8, attribute.name, "on-blur")) {\n                        if (!blurEventElement(node.name)) {\n                            return attrError(node, attribute, on_blur_element_message);\n                        }\n                    } else if (nameInList(node.name, &known_non_hit_target_element_names) and deadHandlerOnNonHitTarget(attribute.name)) {`;
  markup = replaceOnce(markup, validationAnchor, validationReplacement, "blur markup validation anchor changed");
  writeFileSync(markupPath, markup);
}

let ui = readFileSync(uiPath, "utf8");
if (!ui.includes("on_blur: ?Msg")) {
  ui = replaceOnce(ui, "    input,\n    scroll,", "    input,\n    blur,\n    scroll,", "blur handler event anchor changed");
  ui = replaceOnce(ui, "            on_input: ?InputMsgFn = null,\n            /// Message constructor for value changes", "            on_input: ?InputMsgFn = null,\n            /// Void Msg dispatched when this text-entry widget loses canvas focus through a user pointer or keyboard transition.\n            on_blur: ?Msg = null,\n            /// Message constructor for value changes", "blur element options anchor changed");
  ui = replaceOnce(ui, "            on_input: ?InputMsgFn = null,\n            on_value: ?ValueMsgFn = null,", "            on_input: ?InputMsgFn = null,\n            on_blur: ?Msg = null,\n            on_value: ?ValueMsgFn = null,", "blur node anchor changed");
  ui = replaceOnce(ui, "                .on_input = options.on_input,\n                .on_value = options.on_value,", "                .on_input = options.on_input,\n                .on_blur = options.on_blur,\n                .on_value = options.on_value,", "blur node construction anchor changed");
  ui = replaceOnce(ui, "            if (node.on_input) |make| {\n                handlers[handler_len.*] = .{ .id = widget.id, .event = .input, .action = .{ .input = make } };\n                handler_len.* += 1;\n            }\n            if (node.on_value) |make| {", "            if (node.on_input) |make| {\n                handlers[handler_len.*] = .{ .id = widget.id, .event = .input, .action = .{ .input = make } };\n                handler_len.* += 1;\n            }\n            appendHandler(handlers, handler_len, widget.id, .blur, node.on_blur);\n            if (node.on_value) |make| {", "blur handler registration anchor changed");
  ui = replaceOnce(ui, "            if (node.on_input != null) total += 1;\n            if (node.on_value != null) total += 1;", "            if (node.on_input != null) total += 1;\n            if (node.on_blur != null) total += 1;\n            if (node.on_value != null) total += 1;", "blur handler count anchor changed");
  writeFileSync(uiPath, ui);
}

let markupContract = readFileSync(markupContractPath, "utf8");
if (!markupContract.includes("blurEventElement(node.name)")) {
  const anchor = `        const event = attribute.name[3..];\n        const tag = self.findMsg(expression.tag);\n        if (std.mem.eql(u8, event, "input")) {`;
  const replacement = `        const event = attribute.name[3..];\n        const tag = self.findMsg(expression.tag);\n        if (std.mem.eql(u8, event, "blur") and !markup.blurEventElement(node.name)) {\n            return self.failAttr(node, attribute, markup.on_blur_element_message);\n        }\n        if (std.mem.eql(u8, event, "input")) {`;
  markupContract = replaceOnce(markupContract, anchor, replacement, "blur contract anchor changed");
  writeFileSync(markupContractPath, markupContract);
}

let markupCompiled = readFileSync(markupCompiledPath, "utf8");
if (!markupCompiled.includes('event, "blur"')) {
  const anchor = `            if (comptime std.mem.eql(u8, event, "input")) {\n                options.on_input = comptime (inputConstructor(expression.tag) orelse fail(node, "on-input tag must carry a TextInputEvent payload"));\n                return;\n            }\n            if (comptime std.mem.eql(u8, event, "scroll")) {`;
  const replacement = `            if (comptime std.mem.eql(u8, event, "input")) {\n                options.on_input = comptime (inputConstructor(expression.tag) orelse fail(node, "on-input tag must carry a TextInputEvent payload"));\n                return;\n            }\n            if (comptime std.mem.eql(u8, event, "blur")) {\n                comptime {\n                    if (!markup.blurEventElement(node.name)) fail(node, markup.on_blur_element_message);\n                }\n            }\n            if (comptime std.mem.eql(u8, event, "scroll")) {`;
  markupCompiled = replaceOnce(markupCompiled, anchor, replacement, "compiled blur decoder anchor changed");
  markupCompiled = replaceOnce(markupCompiled, `            } else if (comptime std.mem.eql(u8, event, "change")) {\n                options.on_change = msg;\n            } else if (comptime std.mem.eql(u8, event, "submit")) {`, `            } else if (comptime std.mem.eql(u8, event, "change")) {\n                options.on_change = msg;\n            } else if (comptime std.mem.eql(u8, event, "blur")) {\n                options.on_blur = msg;\n            } else if (comptime std.mem.eql(u8, event, "submit")) {`, "compiled blur handler anchor changed");
  writeFileSync(markupCompiledPath, markupCompiled);
}

let markupView = readFileSync(markupViewPath, "utf8");
if (!markupView.includes('event, "blur"')) {
  const anchor = `            if (std.mem.eql(u8, event, "input")) {\n                options.on_input = inputConstructor(expression.tag) orelse {\n                    return self.failVoid(node, "on-input tag must carry a TextInputEvent payload");\n                };\n                return;\n            }\n            if (std.mem.eql(u8, event, "scroll")) {`;
  const replacement = `            if (std.mem.eql(u8, event, "input")) {\n                options.on_input = inputConstructor(expression.tag) orelse {\n                    return self.failVoid(node, "on-input tag must carry a TextInputEvent payload");\n                };\n                return;\n            }\n            if (std.mem.eql(u8, event, "blur") and !markup.blurEventElement(node.name)) {\n                return self.failVoid(node, markup.on_blur_element_message);\n            }\n            if (std.mem.eql(u8, event, "scroll")) {`;
  markupView = replaceOnce(markupView, anchor, replacement, "runtime blur decoder anchor changed");
  markupView = replaceOnce(markupView, `            } else if (std.mem.eql(u8, event, "change")) {\n                options.on_change = msg;\n            } else if (std.mem.eql(u8, event, "submit")) {`, `            } else if (std.mem.eql(u8, event, "change")) {\n                options.on_change = msg;\n            } else if (std.mem.eql(u8, event, "blur")) {\n                options.on_blur = msg;\n            } else if (std.mem.eql(u8, event, "submit")) {`, "runtime blur handler anchor changed");
  writeFileSync(markupViewPath, markupView);
}

let runtimeApi = readFileSync(runtimeApiPath, "utf8");
if (!runtimeApi.includes("blurred_id: canvas.ObjectId = 0")) {
  runtimeApi = replaceOnce(runtimeApi, `    edit: ?canvas.TextInputEvent = null,\n};\n\npub const CanvasWidgetKeyboardEvent = struct {`, `    edit: ?canvas.TextInputEvent = null,\n    /// The editable text widget that lost canvas focus before this pointer event was dispatched.\n    /// 0 means focus was unchanged, the prior target was not text-entry, or this was not a focus gesture.\n    blurred_id: canvas.ObjectId = 0,\n};\n\npub const CanvasWidgetKeyboardEvent = struct {`, "pointer blur payload anchor changed");
  runtimeApi = replaceOnce(runtimeApi, `    terminal_paste: bool = false,\n    /// True when this event is dispatched OUTSIDE a gpu-surface input`, `    terminal_paste: bool = false,\n    /// The editable text widget that lost canvas focus before this keyboard event was routed.\n    blurred_id: canvas.ObjectId = 0,\n    /// True when this event is dispatched OUTSIDE a gpu-surface input` , "keyboard blur payload anchor changed");
  writeFileSync(runtimeApiPath, runtimeApi);
}

let canvasEvents = readFileSync(eventsPath, "utf8");
if (!canvasEvents.includes("updateCanvasWidgetFocusFromPointer(self: *Runtime, pointer_event: CanvasWidgetPointerEvent) anyerror!canvas.ObjectId")) {
  canvasEvents = replaceOnce(canvasEvents, `        pub fn updateCanvasWidgetFocusFromPointer(self: *Runtime, pointer_event: CanvasWidgetPointerEvent) anyerror!void {\n            if (pointer_event.pointer.phase != .down) return;\n            const index = runtimeFindViewIndex(self, pointer_event.window_id, pointer_event.view_label) orelse return;\n            if (self.views[index].kind != .gpu_surface) return;`, `        /// Returns the old focused id only when an editable text widget lost\n        /// focus through this real pointer-down transition. Unmount, window\n        /// deactivation, and programmatic focus remain deliberately outside\n        /// the on-blur contract.\n        pub fn updateCanvasWidgetFocusFromPointer(self: *Runtime, pointer_event: CanvasWidgetPointerEvent) anyerror!canvas.ObjectId {\n            if (pointer_event.pointer.phase != .down) return 0;\n            const index = runtimeFindViewIndex(self, pointer_event.window_id, pointer_event.view_label) orelse return 0;\n            if (self.views[index].kind != .gpu_surface) return 0;`, "pointer blur transition anchor changed");
  canvasEvents = replaceOnce(canvasEvents, `            self.views[index].canvas_widget_focus_visible_keyboard = false;\n            if (self.views[index].canvas_widget_focused_id == next_focus_id and self.views[index].canvas_widget_focus_visible_id == next_focus_visible_id) return;\n            const previous_state = self.views[index].canvasWidgetRenderState();\n            self.views[index].canvas_widget_focused_id = next_focus_id;`, `            self.views[index].canvas_widget_focus_visible_keyboard = false;\n            const previous_focus_id = self.views[index].canvas_widget_focused_id;\n            if (previous_focus_id == next_focus_id and self.views[index].canvas_widget_focus_visible_id == next_focus_visible_id) return 0;\n            var blurred_id: canvas.ObjectId = 0;\n            if (previous_focus_id != 0 and previous_focus_id != next_focus_id) {\n                if (self.views[index].widgetLayoutTree().focusTargetById(previous_focus_id)) |previous| {\n                    if (canvas_widget_runtime.canvasWidgetEditableTextKind(previous.kind)) {\n                        blurred_id = previous_focus_id;\n                    }\n                }\n            }\n            const previous_state = self.views[index].canvasWidgetRenderState();\n            self.views[index].canvas_widget_focused_id = next_focus_id;`, "pointer blur previous-focus anchor changed");
  canvasEvents = replaceOnce(canvasEvents, `            self.views[index].canvas_widget_focus_visible_id = next_focus_visible_id;\n            try invalidateForCanvasWidgetRenderStateChange(self, index, previous_state, self.views[index].canvasWidgetRenderState());\n        }\n\n        pub fn updateCanvasWidgetInteractionFromPointer`, `            self.views[index].canvas_widget_focus_visible_id = next_focus_visible_id;\n            try invalidateForCanvasWidgetRenderStateChange(self, index, previous_state, self.views[index].canvasWidgetRenderState());\n            return blurred_id;\n        }\n\n        pub fn updateCanvasWidgetInteractionFromPointer`, "pointer blur return anchor changed");

  canvasEvents = replaceOnce(canvasEvents, `        pub fn updateCanvasWidgetFocusFromKeyboardInput(self: *Runtime, input_event: GpuSurfaceInputEvent) anyerror!bool {\n            if (input_event.kind != .key_down) return false;`, `        pub fn updateCanvasWidgetFocusFromKeyboardInput(self: *Runtime, input_event: GpuSurfaceInputEvent, blurred_id: *canvas.ObjectId) anyerror!bool {\n            blurred_id.* = 0;\n            if (input_event.kind != .key_down) return false;`, "keyboard blur transition anchor changed");
  canvasEvents = canvasEvents.replaceAll("setCanvasWidgetFocusFromKeyboardMoved(self, index, current_id, entry_id)", "setCanvasWidgetFocusFromKeyboardMoved(self, index, current_id, entry_id, blurred_id)");
  canvasEvents = canvasEvents.replaceAll("setCanvasWidgetFocusFromKeyboardMoved(self, index, current_id, target.id)", "setCanvasWidgetFocusFromKeyboardMoved(self, index, current_id, target.id, blurred_id)");
  canvasEvents = replaceOnce(canvasEvents, `        fn setCanvasWidgetFocusFromKeyboardMoved(self: *Runtime, view_index: usize, previous_id: ?canvas.ObjectId, target_id: canvas.ObjectId) anyerror!bool {\n            try setCanvasWidgetFocusFromKeyboard(self, view_index, target_id);\n            const previous = previous_id orelse 0;\n            return target_id != 0 and target_id != previous;\n        }`, `        fn setCanvasWidgetFocusFromKeyboardMoved(\n            self: *Runtime,\n            view_index: usize,\n            previous_id: ?canvas.ObjectId,\n            target_id: canvas.ObjectId,\n            blurred_id: *canvas.ObjectId,\n        ) anyerror!bool {\n            try setCanvasWidgetFocusFromKeyboard(self, view_index, target_id);\n            const previous = previous_id orelse 0;\n            const moved = target_id != 0 and target_id != previous;\n            if (moved and previous != 0) {\n                if (self.views[view_index].widgetLayoutTree().focusTargetById(previous)) |old_target| {\n                    if (canvas_widget_runtime.canvasWidgetEditableTextKind(old_target.kind)) {\n                        blurred_id.* = previous;\n                    }\n                }\n            }\n            return moved;\n        }`, "keyboard blur moved-focus anchor changed");
  writeFileSync(eventsPath, canvasEvents);
}

canvasEvents = readFileSync(eventsPath, "utf8");
if (canvasEvents.includes(`                            current_id,
                            entry_id,
                        );`)) {
  canvasEvents = replaceOnce(canvasEvents, `                            current_id,
                            entry_id,
                        );`, `                            current_id,
                            entry_id,
                            blurred_id,
                        );`, "combobox Tab blur forwarding anchor changed");
  writeFileSync(eventsPath, canvasEvents);
}

// Tab and Shift+Tab intentionally move an open combobox's focus *into* its
// owned result menu. That is an internal control transition, not a real field
// departure: dispatching `on-blur` there makes a valid provisional result look
// invalid before Enter has had a chance to commit it.
canvasEvents = readFileSync(eventsPath, "utf8");
if (!canvasEvents.includes("moved_into_owned_combobox_menu")) {
  canvasEvents = replaceOnce(canvasEvents, `        fn setCanvasWidgetFocusFromKeyboardMoved(
            self: *Runtime,
            view_index: usize,
            previous_id: ?canvas.ObjectId,
            target_id: canvas.ObjectId,
            blurred_id: *canvas.ObjectId,
        ) anyerror!bool {
            try setCanvasWidgetFocusFromKeyboard(self, view_index, target_id);
            const previous = previous_id orelse 0;
            const moved = target_id != 0 and target_id != previous;
            if (moved and previous != 0) {
                if (self.views[view_index].widgetLayoutTree().focusTargetById(previous)) |old_target| {
                    if (canvas_widget_runtime.canvasWidgetEditableTextKind(old_target.kind)) {
                        blurred_id.* = previous;
                    }
                }
            }
            return moved;
        }`, `        fn setCanvasWidgetFocusFromKeyboardMoved(
            self: *Runtime,
            view_index: usize,
            previous_id: ?canvas.ObjectId,
            target_id: canvas.ObjectId,
            blurred_id: *canvas.ObjectId,
        ) anyerror!bool {
            try setCanvasWidgetFocusFromKeyboard(self, view_index, target_id);
            const previous = previous_id orelse 0;
            const moved = target_id != 0 and target_id != previous;
            const moved_into_owned_combobox_menu = if (previous != 0) blk: {
                const first = self.views[view_index]
                    .canvasWidgetOwnedComboboxMenuEntryId(previous, false) orelse
                    break :blk false;
                const last = self.views[view_index]
                    .canvasWidgetOwnedComboboxMenuEntryId(previous, true) orelse
                    break :blk false;
                break :blk target_id == first or target_id == last;
            } else false;
            if (moved and previous != 0 and !moved_into_owned_combobox_menu) {
                if (self.views[view_index].widgetLayoutTree().focusTargetById(previous)) |old_target| {
                    if (canvas_widget_runtime.canvasWidgetEditableTextKind(old_target.kind)) {
                        blurred_id.* = previous;
                    }
                }
            }
            return moved;
        }`, "combobox menu entry should not emit an early blur");
  writeFileSync(eventsPath, canvasEvents);
}

let contextMenu = readFileSync(contextMenuPath, "utf8");
if (contextMenu.includes("try CanvasWidgetEventMethods().updateCanvasWidgetFocusFromPointer(self, pointer_event);")) {
  contextMenu = contextMenu.replaceAll("                    try CanvasWidgetEventMethods().updateCanvasWidgetFocusFromPointer(self, pointer_event);", "                    _ = try CanvasWidgetEventMethods().updateCanvasWidgetFocusFromPointer(self, pointer_event);");
  writeFileSync(contextMenuPath, contextMenu);
}

let textInput = readFileSync(textInputPath, "utf8");
if (!textInput.includes("comboboxes show it when model-selected")) {
  textInput = replaceOnce(textInput, `/// Whether the field currently shows the built-in trailing clear\n/// affordance: search fields (the searchable kind) show it whenever they\n/// hold text — zero attributes, exactly like the leading glass.\npub fn widgetTextInputShowsClearButton(widget: Widget) bool {\n    return widget.kind == .search_field and widget.text.len > 0 and !widget.state.disabled;\n}`, `/// Whether the field currently shows the built-in trailing clear\n/// affordance: search fields show it whenever they hold text, while\n/// comboboxes show it when model-selected. The combobox's selected bit is\n/// the authoritative committed-choice state, so the affordance does not\n/// disappear merely because the display text is temporarily empty.\npub fn widgetTextInputShowsClearButton(widget: Widget) bool {\n    if (widget.state.disabled) return false;\n    if (widget.kind == .search_field) return widget.text.len > 0;\n    return widget.kind == .combobox and widget.state.selected;\n}`, "combobox selected clear state anchor changed");
  writeFileSync(textInputPath, textInput);
}

let canvasEventsPrimitive = readFileSync(canvasEventsPrimitivePath, "utf8");
if (!canvasEventsPrimitive.includes("widgetKeyboardCommandClearTextEditEvent")) {
  canvasEventsPrimitive = replaceOnce(
    canvasEventsPrimitive,
    `fn widgetKeyboardKeyDownTextEditEvent(event: WidgetKeyboardEvent) ?TextInputEvent {\n    if (widgetKeyboardSelectAllTextEditEvent(event)) |edit| return edit;\n    if (widgetKeyboardCommandTextNavigationEvent(event)) |edit| return edit;`,
    `fn widgetKeyboardKeyDownTextEditEvent(event: WidgetKeyboardEvent) ?TextInputEvent {\n    if (widgetKeyboardSelectAllTextEditEvent(event)) |edit| return edit;\n    if (widgetKeyboardCommandClearTextEditEvent(event)) |edit| return edit;\n    if (widgetKeyboardCommandTextNavigationEvent(event)) |edit| return edit;`,
    "Command+Delete edit routing anchor changed",
  );
  canvasEventsPrimitive = replaceOnce(
    canvasEventsPrimitive,
    `fn widgetKeyboardSelectAllTextEditEvent(event: WidgetKeyboardEvent) ?TextInputEvent {\n    if (!event.modifiers.hasCommandModifier() or event.modifiers.alt or event.modifiers.shift) return null;\n    if (!std.ascii.eqlIgnoreCase(event.key, "a")) return null;\n    return .{ .set_selection = .{ .anchor = 0, .focus = std.math.maxInt(usize) } };\n}\n`,
    `fn widgetKeyboardSelectAllTextEditEvent(event: WidgetKeyboardEvent) ?TextInputEvent {\n    if (!event.modifiers.hasCommandModifier() or event.modifiers.alt or event.modifiers.shift) return null;\n    if (!std.ascii.eqlIgnoreCase(event.key, "a")) return null;\n    return .{ .set_selection = .{ .anchor = 0, .focus = std.math.maxInt(usize) } };\n}\n\n/// macOS Command+Delete/Backspace clears the entire editable value. Keep\n/// this macOS-only (super, not generic control) so the existing Windows\n/// and Linux Ctrl deletion/navigation shortcuts retain their meanings.\n/// Modified variants remain available to app shortcuts.\nfn widgetKeyboardCommandClearTextEditEvent(event: WidgetKeyboardEvent) ?TextInputEvent {\n    if (!event.modifiers.super or event.modifiers.alt or event.modifiers.shift) return null;\n    if (std.ascii.eqlIgnoreCase(event.key, "backspace") or\n        std.ascii.eqlIgnoreCase(event.key, "delete")) return .clear;\n    return null;\n}\n`,
    "Command+Delete helper anchor changed",
  );
  writeFileSync(canvasEventsPrimitivePath, canvasEventsPrimitive);
}

let controlRender = readFileSync(controlRenderPath, "utf8");
if (!controlRender.includes("A selected combobox exposes the shared text-clear affordance")) {
  controlRender = replaceOnce(controlRender, "const textInputClearButtonRect = widget_text_input.textInputClearButtonRect;", "const textInputClearButtonRect = widget_text_input.textInputClearButtonRect;\nconst widgetTextInputShowsClearButton = widget_text_input.widgetTextInputShowsClearButton;", "combobox clear helper import anchor changed");
  controlRender = replaceOnce(controlRender, `    if (widget.kind == .combobox) {\n        try emitComboboxChevron(builder, widget, tokens, visual);\n    }\n    try emitSearchFieldClearButton(builder, widget, tokens, visual);`, `    // A selected combobox exposes the shared text-clear affordance in the\n    // same trailing slot as its chevron. Clear wins over the chevron: it is\n    // the actionable state, while expanded only describes the open menu.\n    if (widget.kind == .combobox and widgetTextInputShowsClearButton(widget)) {\n        try emitSearchFieldClearButton(builder, widget, tokens, visual);\n    } else {\n        if (widget.kind == .combobox) {\n            try emitComboboxChevron(builder, widget, tokens, visual);\n        }\n        try emitSearchFieldClearButton(builder, widget, tokens, visual);\n    }`, "combobox clear/chevron render anchor changed");
  controlRender = replaceOnce(controlRender, `fn emitComboboxChevron(builder: *Builder, widget: Widget, tokens: DesignTokens, visual: ControlVisualTokens) Error!void {\n    const icon = icon_model.resolve("chevron-down") orelse return;`, `fn emitComboboxChevron(builder: *Builder, widget: Widget, tokens: DesignTokens, visual: ControlVisualTokens) Error!void {\n    const icon = icon_model.resolve(if (widget.state.expanded orelse false) "chevron-up" else "chevron-down") orelse return;`, "combobox expanded chevron anchor changed");
  writeFileSync(controlRenderPath, controlRender);
}

textInput = readFileSync(textInputPath, "utf8");
if (textInput.includes("widget.state.selected orelse false")) {
  textInput = textInput.replaceAll("widget.state.selected orelse false", "widget.state.selected");
  writeFileSync(textInputPath, textInput);
}

controlRender = readFileSync(controlRenderPath, "utf8");
if (controlRender.includes("A selected combobox exposes the shared text-clear affordance") && !controlRender.includes("const widgetTextInputShowsClearButton = widget_text_input.widgetTextInputShowsClearButton;")) {
  controlRender = replaceOnce(controlRender, "const textInputClearButtonRect = widget_text_input.textInputClearButtonRect;", "const textInputClearButtonRect = widget_text_input.textInputClearButtonRect;\nconst widgetTextInputShowsClearButton = widget_text_input.widgetTextInputShowsClearButton;", "combobox clear helper recovery anchor changed");
  writeFileSync(controlRenderPath, controlRender);
}

let gpuSurfaceEvents = readFileSync(gpuSurfaceEventsPath, "utf8");
if (!gpuSurfaceEvents.includes("pointer_event.blurred_id = try CanvasWidgetEventMethods().updateCanvasWidgetFocusFromPointer")) {
  gpuSurfaceEvents = replaceOnce(gpuSurfaceEvents, "                    try CanvasWidgetEventMethods().updateCanvasWidgetFocusFromPointer(self, pointer_event.*);", "                    pointer_event.blurred_id = try CanvasWidgetEventMethods().updateCanvasWidgetFocusFromPointer(self, pointer_event.*);", "pointer blur event plumbing anchor changed");
  gpuSurfaceEvents = replaceOnce(gpuSurfaceEvents, `            const widget_focus_moved = if (widget_surface_dismissed or targetless_composition_owns_keys or terminal_key_lifetime_suppressed)\n                false\n            else\n                try CanvasWidgetEventMethods().updateCanvasWidgetFocusFromKeyboardInput(self, input_event);\n            var widget_keyboard_event =`, `            var widget_blurred_id: canvas.ObjectId = 0;\n            const widget_focus_moved = if (widget_surface_dismissed or targetless_composition_owns_keys or terminal_key_lifetime_suppressed)\n                false\n            else\n                try CanvasWidgetEventMethods().updateCanvasWidgetFocusFromKeyboardInput(self, input_event, &widget_blurred_id);\n            var widget_keyboard_event =`, "keyboard blur event plumbing anchor changed");
  gpuSurfaceEvents = replaceOnce(gpuSurfaceEvents, `            if (widget_keyboard_event) |*keyboard_event| {\n                keyboard_event.keyboard.focus_moved = widget_focus_moved;\n            }`, `            if (widget_keyboard_event) |*keyboard_event| {\n                keyboard_event.keyboard.focus_moved = widget_focus_moved;\n                keyboard_event.blurred_id = widget_blurred_id;\n            }`, "keyboard blur assignment anchor changed");
  writeFileSync(gpuSurfaceEventsPath, gpuSurfaceEvents);
}

let uiApp = readFileSync(uiAppPath, "utf8");
if (!uiApp.includes("pointer_event.blurred_id")) {
  uiApp = replaceOnce(uiApp, `        fn handlePointer(self: *Self, runtime: *Runtime, pointer_event: core.CanvasWidgetPointerEvent) anyerror!void {\n            const tree = self.treeForViewLabel(pointer_event.view_label) orelse return;\n            const terminal_selected = try self.handleTerminalPointer(runtime, pointer_event);`, `        fn handlePointer(self: *Self, runtime: *Runtime, pointer_event: core.CanvasWidgetPointerEvent) anyerror!void {\n            const tree = self.treeForViewLabel(pointer_event.view_label) orelse return;\n            // Focus changes before pointer activation. Dispatch the old text\n            // field's commit/normalization message before the new target's\n            // edit or press, matching the desktop blur-before-click order.\n            if (pointer_event.blurred_id != 0) {\n                if (tree.msgFor(pointer_event.blurred_id, .blur)) |msg| {\n                    try self.dispatch(runtime, pointer_event.window_id, msg);\n                }\n            }\n            const terminal_selected = try self.handleTerminalPointer(runtime, pointer_event);`, "ui-app pointer blur dispatch anchor changed");
  uiApp = replaceOnce(uiApp, `        fn handleKeyboard(self: *Self, runtime: *Runtime, keyboard_event: core.CanvasWidgetKeyboardEvent) anyerror!void {\n            const tree = self.treeForViewLabel(keyboard_event.view_label) orelse return;\n            // Key precedence, top to bottom`, `        fn handleKeyboard(self: *Self, runtime: *Runtime, keyboard_event: core.CanvasWidgetKeyboardEvent) anyerror!void {\n            const tree = self.treeForViewLabel(keyboard_event.view_label) orelse return;\n            // Tab/Shift+Tab already moved the runtime focus before routing\n            // this key to its new target. Commit the old text field first.\n            if (keyboard_event.blurred_id != 0) {\n                if (tree.msgFor(keyboard_event.blurred_id, .blur)) |msg| {\n                    try self.dispatch(runtime, keyboard_event.window_id, msg);\n                }\n            }\n            // Key precedence, top to bottom`, "ui-app keyboard blur dispatch anchor changed");
  writeFileSync(uiAppPath, uiApp);
}

let viewTree = readFileSync(viewTreePath, "utf8");
if (!viewTree.includes("canvasWidgetOwnedComboboxMenuEntryId")) {
  const helper = `    /// A combobox trigger enters its owned menu through the same marked-row
    /// rule as ArrowDown/ArrowUp. Tab uses this only while focus is still on
    /// the trigger; Tab from a menu row keeps the normal dismissal behavior.
    pub fn canvasWidgetOwnedComboboxMenuEntryId(
        self: *const RuntimeView,
        focused_id: canvas.ObjectId,
        from_end: bool,
    ) ?canvas.ObjectId {
        const focused_index = self.canvasWidgetNodeIndexById(focused_id) orelse
            return null;
        if (self.widget_layout_nodes[focused_index].widget.kind != .combobox)
            return null;
        const surface_index = self.canvasWidgetOwnedMenuSurfaceIndex(
            focused_index,
        ) orelse return null;
        return self.canvasWidgetMenuSurfaceEntryId(surface_index, from_end);
    }

`;
  const anchor = "    /// The focusable trigger the dismissed anchored surface returns\n";
  viewTree = replaceOnce(viewTree, anchor, `${helper}${anchor}`, "view helper anchor changed");
  writeFileSync(viewTreePath, viewTree);
}

viewTree = readFileSync(viewTreePath, "utf8");
if (!viewTree.includes("canvasWidgetFocusedInOwnedComboboxMenu")) {
  const helper = `    /// Whether keyboard focus is on an entry inside a combobox-owned result
    /// menu. This keeps Tab scoped to the combobox without changing the
    /// established Tab-dismissal behavior of selects and generic menus.
    pub fn canvasWidgetFocusedInOwnedComboboxMenu(
        self: *const RuntimeView,
        focused_id: canvas.ObjectId,
    ) bool {
        const focused_index = self.canvasWidgetNodeIndexById(focused_id) orelse
            return false;
        for (self.widget_layout_nodes[0..self.widget_layout_node_count], 0..) |node, node_index| {
            if (node.widget.kind != .combobox) continue;
            const surface_index = self.canvasWidgetOwnedMenuSurfaceIndex(
                node_index,
            ) orelse continue;
            if (self.canvasWidgetNodeIndexDescendsFrom(focused_index, surface_index)) {
                return true;
            }
        }
        return false;
    }

`;
  const anchor = "    /// The focusable trigger the dismissed anchored surface returns\n";
  viewTree = replaceOnce(viewTree, anchor, `${helper}${anchor}`, "combobox menu focus helper anchor changed");
  writeFileSync(viewTreePath, viewTree);
}

let view = readFileSync(viewPath, "utf8");
if (!view.includes("canvasWidgetOwnedComboboxMenuEntryId")) {
  const anchor = "    pub const canvasWidgetMenuSurfaceEntryId = CanvasWidgetTreeMethods.canvasWidgetMenuSurfaceEntryId;\n";
  const exportLine = "    pub const canvasWidgetOwnedComboboxMenuEntryId = CanvasWidgetTreeMethods.canvasWidgetOwnedComboboxMenuEntryId;\n";
  view = replaceOnce(view, anchor, `${anchor}${exportLine}`, "RuntimeView export anchor changed");
  writeFileSync(viewPath, view);
}

view = readFileSync(viewPath, "utf8");
if (!view.includes("canvasWidgetFocusedInOwnedComboboxMenu")) {
  const anchor = "    pub const canvasWidgetOwnedComboboxMenuEntryId = CanvasWidgetTreeMethods.canvasWidgetOwnedComboboxMenuEntryId;\n";
  const exportLine = "    pub const canvasWidgetFocusedInOwnedComboboxMenu = CanvasWidgetTreeMethods.canvasWidgetFocusedInOwnedComboboxMenu;\n";
  view = replaceOnce(view, anchor, `${anchor}${exportLine}`, "RuntimeView combobox menu focus export anchor changed");
  writeFileSync(viewPath, view);
}

let events = readFileSync(eventsPath, "utf8");
if (!events.includes("A combobox uses Tab/Shift+Tab to enter its visible result") && !events.includes("A combobox Tab stays within its owned result menu")) {
  const dismissalAnchor = `            if (tab and focused_id == 0) return 0;

            const previous_cursor = self.views[index].canvas_widget_cursor;`;
  const dismissalReplacement = `            if (tab and focused_id == 0) return 0;

            // A combobox uses Tab/Shift+Tab to enter its visible result
            // list, just like ArrowDown/ArrowUp. Keep the anchored menu
            // mounted so the query and provisional choice survive until
            // Enter commits a row. A Tab from an already focused row still
            // follows the ordinary menu-dismissal path below.
            if (tab and self.views[index].canvasWidgetOwnedComboboxMenuEntryId(
                focused_id,
                modifiers.shift,
            ) != null) return 0;

            const previous_cursor = self.views[index].canvas_widget_cursor;`;
  events = replaceOnce(
    events,
    dismissalAnchor,
    dismissalReplacement,
    "dismissal anchor changed",
  );

  const focusAnchor = `                    if (layout.focusTargetById(id)) |current| {
                        if (canvasWidgetTerminalOwnsTabInput(layout, current)) return false;
                    }
                }
                const direction: canvas.WidgetFocusDirection = if (input_event.modifiers.shift) .backward else .forward;`;
  const focusReplacement = `                    if (layout.focusTargetById(id)) |current| {
                        if (canvasWidgetTerminalOwnsTabInput(layout, current)) return false;
                    }
                    if (self.views[index].canvasWidgetOwnedComboboxMenuEntryId(
                        id,
                        input_event.modifiers.shift,
                    )) |entry_id| {
                        return try setCanvasWidgetFocusFromKeyboardMoved(
                            self,
                            index,
                            current_id,
                            entry_id,
                            blurred_id,
                        );
                    }
                }
                const direction: canvas.WidgetFocusDirection = if (input_event.modifiers.shift) .backward else .forward;`;
  events = replaceOnce(events, focusAnchor, focusReplacement, "focus anchor changed");
  writeFileSync(eventsPath, events);
}

events = readFileSync(eventsPath, "utf8");
if (!events.includes("A combobox Tab stays within its owned result menu")) {
  const legacyGuard = `            // A combobox uses Tab/Shift+Tab to enter its visible result
            // list, just like ArrowDown/ArrowUp. Keep the anchored menu
            // mounted so the query and provisional choice survive until
            // Enter commits a row. A Tab from an already focused row still
            // follows the ordinary menu-dismissal path below.
            if (tab and self.views[index].canvasWidgetOwnedComboboxMenuEntryId(
                focused_id,
                modifiers.shift,
            ) != null) return 0;`;
  const replacement = `            // A combobox Tab stays within its owned result menu until Enter
            // commits a row, preserving the query and provisional choice.
            if (tab and (
                self.views[index].canvasWidgetOwnedComboboxMenuEntryId(
                    focused_id,
                    modifiers.shift,
                ) != null or
                self.views[index].canvasWidgetFocusedInOwnedComboboxMenu(focused_id)
            )) return 0;`;
  events = replaceOnce(events, legacyGuard, replacement, "combobox Tab menu retention anchor changed");
  writeFileSync(eventsPath, events);
}

let uiAppTests = readFileSync(uiAppTestsPath, "utf8");
if (!uiAppTests.includes("text-entry on-blur dispatches on Tab and pointer focus transitions")) {
  uiAppTests = replaceOnce(uiAppTests, `    query_edits: u32 = 0,\n};`, `    query_edits: u32 = 0,\n    blur_count: u32 = 0,\n};`, "blur test model anchor changed");
  uiAppTests = replaceOnce(uiAppTests, `    query_edit: canvas.TextInputEvent,\n    note_edit: canvas.TextInputEvent,`, `    query_edit: canvas.TextInputEvent,\n    note_edit: canvas.TextInputEvent,\n    blurred,`, "blur test message anchor changed");
  uiAppTests = replaceOnce(uiAppTests, `        .note_edit => |edit| model.note.apply(edit),\n    }`, `        .note_edit => |edit| model.note.apply(edit),\n        .blurred => model.blur_count += 1,\n    }`, "blur test update anchor changed");
  uiAppTests = replaceOnce(uiAppTests, `        .on_input = ComboMirrorApp.Ui.inputMsg(.query_edit),\n    }, .{});`, `        .on_input = ComboMirrorApp.Ui.inputMsg(.query_edit),\n        .on_blur = .blurred,\n    }, .{});`, "combobox blur binding anchor changed");
  uiAppTests = replaceOnce(uiAppTests, `            .on_input = ComboMirrorApp.Ui.inputMsg(.note_edit),\n        }, .{}),`, `            .on_input = ComboMirrorApp.Ui.inputMsg(.note_edit),\n            .on_blur = .blurred,\n        }, .{}),`, "text-field blur binding anchor changed");
  const blurRegressionTest = `test "text-entry on-blur dispatches on Tab and pointer focus transitions" {\n    const harness = try core.TestHarness().create(std.testing.allocator, .{\n        .size = geometry.SizeF.init(400, 300),\n    });\n    defer harness.destroy(std.testing.allocator);\n    harness.null_platform.gpu_surfaces = true;\n\n    const app_state = try std.testing.allocator.create(ComboMirrorApp);\n    defer std.testing.allocator.destroy(app_state);\n    app_state.* = ComboMirrorApp.init(std.heap.page_allocator, .{}, .{\n        .name = "ui-app-text-entry-blur",\n        .scene = combo_mirror_scene,\n        .canvas_label = combo_mirror_canvas_label,\n        .update = comboMirrorUpdate,\n        .view = comboMirrorView,\n    });\n    defer app_state.deinit();\n    const app = app_state.app();\n    try harness.start(app);\n    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_frame = .{\n        .label = combo_mirror_canvas_label,\n        .size = geometry.SizeF.init(400, 300),\n        .scale_factor = 1,\n        .frame_index = 1,\n        .timestamp_ns = 1_000_000,\n        .nonblank = true,\n    } });\n\n    const combo_id = findWidgetIdByKind(app_state.tree.?.root, .combobox).?;\n    const note_id = findWidgetIdByKind(app_state.tree.?.root, .text_field).?;\n    // Programmatic/automation focus is intentionally outside this event's\n    // contract; the next real Tab transition emits exactly once.\n    try core.testing.dispatchAutomationWidgetAction(&harness.runtime, app, .{\n        .view_label = combo_mirror_canvas_label,\n        .id = combo_id,\n        .action = .focus,\n    });\n    try std.testing.expectEqual(@as(u32, 0), app_state.model.blur_count);\n    try comboMirrorKey(harness, app, "tab");\n    try std.testing.expectEqual(@as(u32, 1), app_state.model.blur_count);\n    try std.testing.expectEqual(note_id, harness.runtime.views[0].canvas_widget_focused_id);\n\n    const combo_frame = (try harness.runtime.canvasWidgetLayout(1, combo_mirror_canvas_label)).findById(combo_id).?.frame;\n    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{\n        .window_id = 1,\n        .label = combo_mirror_canvas_label,\n        .kind = .pointer_down,\n        .x = combo_frame.x + 4,\n        .y = combo_frame.y + combo_frame.height * 0.5,\n        .timestamp_ns = 2_000_000,\n    } });\n    try std.testing.expectEqual(@as(u32, 2), app_state.model.blur_count);\n    try std.testing.expectEqual(combo_id, harness.runtime.views[0].canvas_widget_focused_id);\n\n    // Re-clicking the focused field changes no focus register and emits no\n    // duplicate blur.\n    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{\n        .window_id = 1,\n        .label = combo_mirror_canvas_label,\n        .kind = .pointer_down,\n        .x = combo_frame.x + 4,\n        .y = combo_frame.y + combo_frame.height * 0.5,\n        .timestamp_ns = 3_000_000,\n    } });\n    try std.testing.expectEqual(@as(u32, 2), app_state.model.blur_count);\n}\n\n`;
  // This is an upstream test that exists in an unmodified 0.6.1 install.
  // The open-combobox regression is added later in this script, so it cannot
  // serve as an anchor during npm postinstall from a cold cache.
  const blurAnchor = "test \"a closed combobox's open arrows move neither the retained caret nor the model mirror\" {";
  uiAppTests = replaceOnce(uiAppTests, blurAnchor, `${blurRegressionTest}${blurAnchor}`, "blur regression test anchor changed");
  writeFileSync(uiAppTestsPath, uiAppTests);
}

uiAppTests = readFileSync(uiAppTestsPath, "utf8");
if (!uiAppTests.includes("macOS Command+Delete clears text-entry widgets through on-input")) {
  const commandDeleteRegressionTest = `test "macOS Command+Delete clears text-entry widgets through on-input" {
    const harness = try core.TestHarness().create(std.testing.allocator, .{
        .size = geometry.SizeF.init(400, 300),
    });
    defer harness.destroy(std.testing.allocator);
    harness.null_platform.gpu_surfaces = true;

    const app_state = try std.testing.allocator.create(ComboMirrorApp);
    defer std.testing.allocator.destroy(app_state);
    app_state.* = ComboMirrorApp.init(std.heap.page_allocator, .{}, .{
        .name = "ui-app-command-delete",
        .scene = combo_mirror_scene,
        .canvas_label = combo_mirror_canvas_label,
        .update = comboMirrorUpdate,
        .view = comboMirrorView,
    });
    defer app_state.deinit();
    app_state.model.query.set("glass");
    app_state.model.note.set("draft");
    const app = app_state.app();
    try harness.start(app);
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_frame = .{
        .label = combo_mirror_canvas_label,
        .size = geometry.SizeF.init(400, 300),
        .scale_factor = 1,
        .frame_index = 1,
        .timestamp_ns = 1_000_000,
        .nonblank = true,
    } });

    const combo_id = findWidgetIdByKind(app_state.tree.?.root, .combobox).?;
    try core.testing.dispatchAutomationWidgetAction(&harness.runtime, app, .{
        .view_label = combo_mirror_canvas_label,
        .id = combo_id,
        .action = .focus,
    });
    const edits_before_clear = app_state.model.query_edits;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = combo_mirror_canvas_label,
        .kind = .key_down,
        .key = "backspace",
        .modifiers = .{ .super = true },
    } });
    try std.testing.expectEqualStrings("", app_state.model.query.text());
    try std.testing.expectEqual(edits_before_clear + 1, app_state.model.query_edits);
    var retained = try harness.runtime.canvasWidgetLayout(1, combo_mirror_canvas_label);
    try std.testing.expectEqualStrings("", retained.findById(combo_id).?.widget.text);

    // The forward-delete key label on compact macOS keyboards follows the
    // same event pipeline. Type first so this proves it clears rather than
    // merely accepting the shortcut on an already-empty field.
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = combo_mirror_canvas_label,
        .kind = .text_input,
        .text = "jar",
    } });
    try std.testing.expectEqualStrings("jar", app_state.model.query.text());
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = combo_mirror_canvas_label,
        .kind = .key_down,
        .key = "delete",
        .modifiers = .{ .super = true },
    } });
    try std.testing.expectEqualStrings("", app_state.model.query.text());
    retained = try harness.runtime.canvasWidgetLayout(1, combo_mirror_canvas_label);
    try std.testing.expectEqualStrings("", retained.findById(combo_id).?.widget.text);

    // The same generic editor edit clears an ordinary text field through
    // its existing on-input constructor, not a combobox-only special case.
    const note_id = findWidgetIdByKind(app_state.tree.?.root, .text_field).?;
    try core.testing.dispatchAutomationWidgetAction(&harness.runtime, app, .{
        .view_label = combo_mirror_canvas_label,
        .id = note_id,
        .action = .focus,
    });
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = combo_mirror_canvas_label,
        .kind = .key_down,
        .key = "backspace",
        .modifiers = .{ .super = true },
    } });
    try std.testing.expectEqualStrings("", app_state.model.note.text());
    retained = try harness.runtime.canvasWidgetLayout(1, combo_mirror_canvas_label);
    try std.testing.expectEqualStrings("", retained.findById(note_id).?.widget.text);
}

`;
  // This is also present in a pristine SDK install. The open-combobox test is
  // inserted below, so it cannot anchor an earlier postinstall insertion.
  const commandDeleteAnchor = "test \"a closed combobox's open arrows move neither the retained caret nor the model mirror\" {";
  uiAppTests = replaceOnce(
    uiAppTests,
    commandDeleteAnchor,
    `${commandDeleteRegressionTest}${commandDeleteAnchor}`,
    "Command+Delete regression test anchor changed",
  );
  writeFileSync(uiAppTestsPath, uiAppTests);
}

if (!uiAppTests.includes("an open combobox enters its menu on Tab without dismissing")) {
  const regressionTest = `test "an open combobox enters its menu on Tab without dismissing" {
    const harness = try core.TestHarness().create(std.testing.allocator, .{
        .size = geometry.SizeF.init(400, 300),
    });
    defer harness.destroy(std.testing.allocator);
    harness.null_platform.gpu_surfaces = true;

    const app_state = try std.testing.allocator.create(ComboMirrorApp);
    defer std.testing.allocator.destroy(app_state);
    app_state.* = ComboMirrorApp.init(std.heap.page_allocator, .{}, .{
        .name = "ui-app-combo-mirror-tab-entry",
        .scene = combo_mirror_scene,
        .canvas_label = combo_mirror_canvas_label,
        .update = comboMirrorUpdate,
        .view = comboMirrorView,
    });
    defer app_state.deinit();
    app_state.model.query.set("glass");
    const app = app_state.app();
    try harness.start(app);
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_frame = .{
        .label = combo_mirror_canvas_label,
        .size = geometry.SizeF.init(400, 300),
        .scale_factor = 1,
        .frame_index = 1,
        .timestamp_ns = 1_000_000,
        .nonblank = true,
    } });

    const combo_id = findWidgetIdByKind(app_state.tree.?.root, .combobox).?;
    try core.testing.dispatchAutomationWidgetAction(&harness.runtime, app, .{
        .view_label = combo_mirror_canvas_label,
        .id = combo_id,
        .action = .focus,
    });
    try comboMirrorKey(harness, app, "arrowdown");
    try std.testing.expect(app_state.model.open);
    try std.testing.expectEqual(combo_id, harness.runtime.views[0].canvas_widget_focused_id);

    const first_item_id = findWidgetIdByText(app_state.tree.?, .menu_item, "glass bead").?;
    const last_item_id = findWidgetIdByText(app_state.tree.?, .menu_item, "glass jar").?;
    try comboMirrorKey(harness, app, "tab");
    try std.testing.expect(app_state.model.open);
    try std.testing.expectEqualStrings("glass", app_state.model.query.text());
    try std.testing.expectEqual(first_item_id, harness.runtime.views[0].canvas_widget_focused_id);

    // Enter remains the normal row-activation path and returns focus to its
    // combobox trigger when the model closes the menu.
    try comboMirrorKey(harness, app, "enter");
    try std.testing.expect(!app_state.model.open);
    try std.testing.expectEqual(combo_id, harness.runtime.views[0].canvas_widget_focused_id);

    // Shift+Tab uses the same unmarked-last-row entry rule as ArrowUp.
    try comboMirrorKey(harness, app, "arrowup");
    try std.testing.expect(app_state.model.open);
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = combo_mirror_canvas_label,
        .kind = .key_down,
        .key = "tab",
        .modifiers = .{ .shift = true },
    } });
    try std.testing.expect(app_state.model.open);
    try std.testing.expectEqualStrings("glass", app_state.model.query.text());
    try std.testing.expectEqual(last_item_id, harness.runtime.views[0].canvas_widget_focused_id);
}

`;
  const anchor = 'test "a closed combobox\'s open arrows move neither the retained caret nor the model mirror" {';
  uiAppTests = replaceOnce(
    uiAppTests,
    anchor,
    `${regressionTest}${anchor}`,
    "combobox regression test anchor changed",
  );
  writeFileSync(uiAppTestsPath, uiAppTests);
}

// Entering an owned result menu is a combobox-internal focus transition. Its
// trigger must not emit a blur before the highlighted option can be committed.
uiAppTests = readFileSync(uiAppTestsPath, "utf8");
if (!uiAppTests.includes("combobox Tab menu entry does not emit an early blur")) {
  uiAppTests = replaceOnce(uiAppTests, `    try comboMirrorKey(harness, app, "tab");
    try std.testing.expect(app_state.model.open);
    try std.testing.expectEqualStrings("glass", app_state.model.query.text());
    try std.testing.expectEqual(first_item_id, harness.runtime.views[0].canvas_widget_focused_id);`, `    try comboMirrorKey(harness, app, "tab");
    try std.testing.expect(app_state.model.open);
    try std.testing.expectEqualStrings("glass", app_state.model.query.text());
    try std.testing.expectEqual(first_item_id, harness.runtime.views[0].canvas_widget_focused_id);
    // combobox Tab menu entry does not emit an early blur
    try std.testing.expectEqual(@as(u32, 0), app_state.model.blur_count);`, "combobox Tab blur regression assertion anchor changed");
  writeFileSync(uiAppTestsPath, uiAppTests);
}

uiAppTests = readFileSync(uiAppTestsPath, "utf8");
if (!uiAppTests.includes("Repeated Tab and Shift+Tab cycle an open combobox result menu")) {
  const anchor = `    // Enter remains the normal row-activation path and returns focus to its
    // combobox trigger when the model closes the menu.`;
  const regression = `    // Repeated Tab and Shift+Tab cycle an open combobox result menu without
    // dismissing it, matching the ArrowDown/ArrowUp focus behavior.
    try comboMirrorKey(harness, app, "tab");
    try std.testing.expect(app_state.model.open);
    try std.testing.expectEqual(last_item_id, harness.runtime.views[0].canvas_widget_focused_id);

    try comboMirrorKey(harness, app, "tab");
    try std.testing.expect(app_state.model.open);
    try std.testing.expectEqual(first_item_id, harness.runtime.views[0].canvas_widget_focused_id);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = combo_mirror_canvas_label,
        .kind = .key_down,
        .key = "tab",
        .modifiers = .{ .shift = true },
    } });
    try std.testing.expect(app_state.model.open);
    try std.testing.expectEqual(last_item_id, harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqualStrings("glass", app_state.model.query.text());

`;
  uiAppTests = replaceOnce(uiAppTests, anchor, `${regression}${anchor}`, "repeated combobox Tab regression anchor changed");
  writeFileSync(uiAppTestsPath, uiAppTests);
}

let anchoredTests = readFileSync(anchoredTestsPath, "utf8");
if (!anchoredTests.includes("anchored select: Tab from its open trigger still dismisses")) {
  const selectRegressionTest = `test "anchored select: Tab from its open trigger still dismisses" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const trigger_id = fixture.widgetIdByText(.select, "Repo").?;
    var command_buffer: [96]u8 = undefined;
    const focus_command = try std.fmt.bufPrint(
        &command_buffer,
        "widget-action {s} {d} focus",
        .{ canvas_label, trigger_id },
    );
    try fixture.harness.runtime.dispatchAutomationCommand(
        fixture.app,
        focus_command,
    );
    try fixture.key("arrowdown");
    try std.testing.expect(fixture.app_state.model.open);
    try std.testing.expectEqual(
        trigger_id,
        fixture.harness.runtime.views[0].canvas_widget_focused_id,
    );

    try fixture.key("tab");
    try std.testing.expect(!fixture.app_state.model.open);
    try std.testing.expectEqual(@as(u32, 1), fixture.app_state.model.dismissals);
    try std.testing.expectEqual(
        trigger_id,
        fixture.harness.runtime.views[0].canvas_widget_focused_id,
    );
}

`;
  const anchor = 'test "anchored picker: Tab while inside the open menu dismisses without committing" {';
  anchoredTests = replaceOnce(
    anchoredTests,
    anchor,
    `${selectRegressionTest}${anchor}`,
    "select Tab regression test anchor changed",
  );
  writeFileSync(anchoredTestsPath, anchoredTests);
}
