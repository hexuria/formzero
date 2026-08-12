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
const flowPath = resolve(nativeSdkRoot, "src/runtime/flow.zig");
const corePath = resolve(nativeSdkRoot, "src/runtime/core.zig");
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

function applyFocusPatch() {
// `on-focus` has the same deliberately small contract as `on-blur`: it is a
// commit/presentation hook for text-entry controls, not a general focus
// observer for every button or menu row in the canvas. Keep it separate from
// the blur insertion above so a cold 0.6.1 install is first brought to the
// existing patch baseline, then receives this additive event.
schema = readFileSync(schemaPath, "utf8");
if (!schema.includes('.name = "focus", .dead_on_non_hit_target = true')) {
  const anchor = '    .{ .code = 14, .name = "blur", .dead_on_non_hit_target = true },\n';
  const replacement = `${anchor}    // Text-entry focus arrived through a real pointer or keyboard transition.\n    .{ .code = 15, .name = "focus", .dead_on_non_hit_target = true },\n`;
  schema = replaceOnce(schema, anchor, replacement, "focus schema anchor changed");
  writeFileSync(schemaPath, schema);
}

markup = readFileSync(markupPath, "utf8");
if (!markup.includes("pub const on_focus_element_message")) {
  const anchor = 'pub const on_blur_element_message = "on-blur is only supported on text-entry controls (input, text-field, search-field, combobox, textarea) - it dispatches when keyboard focus moves away through a pointer or keyboard focus transition";\n';
  const replacement = `${anchor}pub const on_focus_element_message = "on-focus is only supported on text-entry controls (input, text-field, search-field, combobox, textarea) - it dispatches when keyboard focus arrives through a pointer or keyboard focus transition";\n`;
  markup = replaceOnce(markup, anchor, replacement, "focus markup message anchor changed");
  const validationAnchor = `                    } else if (std.mem.eql(u8, attribute.name, "on-blur")) {\n                        if (!blurEventElement(node.name)) {\n                            return attrError(node, attribute, on_blur_element_message);\n                        }\n                    } else if (nameInList(node.name, &known_non_hit_target_element_names) and deadHandlerOnNonHitTarget(attribute.name)) {`;
  const validationReplacement = `                    } else if (std.mem.eql(u8, attribute.name, "on-blur")) {\n                        if (!blurEventElement(node.name)) {\n                            return attrError(node, attribute, on_blur_element_message);\n                        }\n                    } else if (std.mem.eql(u8, attribute.name, "on-focus")) {\n                        if (!blurEventElement(node.name)) {\n                            return attrError(node, attribute, on_focus_element_message);\n                        }\n                    } else if (nameInList(node.name, &known_non_hit_target_element_names) and deadHandlerOnNonHitTarget(attribute.name)) {`;
  markup = replaceOnce(markup, validationAnchor, validationReplacement, "focus markup validation anchor changed");
  writeFileSync(markupPath, markup);
}

ui = readFileSync(uiPath, "utf8");
if (!ui.includes("on_focus: ?Msg")) {
  ui = replaceOnce(ui, "    input,\n    blur,\n    scroll,", "    input,\n    blur,\n    focus,\n    scroll,", "focus handler event anchor changed");
  ui = replaceOnce(ui, "            /// Void Msg dispatched when this text-entry widget loses canvas focus through a user pointer or keyboard transition.\n            on_blur: ?Msg = null,\n            /// Message constructor for value changes", "            /// Void Msg dispatched when this text-entry widget loses canvas focus through a user pointer or keyboard transition.\n            on_blur: ?Msg = null,\n            /// Void Msg dispatched when this text-entry widget gains canvas focus through a user pointer or keyboard transition.\n            on_focus: ?Msg = null,\n            /// Message constructor for value changes", "focus element options anchor changed");
  ui = replaceOnce(ui, "            on_input: ?InputMsgFn = null,\n            on_blur: ?Msg = null,\n            on_value: ?ValueMsgFn = null,", "            on_input: ?InputMsgFn = null,\n            on_blur: ?Msg = null,\n            on_focus: ?Msg = null,\n            on_value: ?ValueMsgFn = null,", "focus node anchor changed");
  ui = replaceOnce(ui, "                .on_input = options.on_input,\n                .on_blur = options.on_blur,\n                .on_value = options.on_value,", "                .on_input = options.on_input,\n                .on_blur = options.on_blur,\n                .on_focus = options.on_focus,\n                .on_value = options.on_value,", "focus node construction anchor changed");
  ui = replaceOnce(ui, "            appendHandler(handlers, handler_len, widget.id, .blur, node.on_blur);\n            if (node.on_value) |make| {", "            appendHandler(handlers, handler_len, widget.id, .blur, node.on_blur);\n            appendHandler(handlers, handler_len, widget.id, .focus, node.on_focus);\n            if (node.on_value) |make| {", "focus handler registration anchor changed");
  ui = replaceOnce(ui, "            if (node.on_blur != null) total += 1;\n            if (node.on_value != null) total += 1;", "            if (node.on_blur != null) total += 1;\n            if (node.on_focus != null) total += 1;\n            if (node.on_value != null) total += 1;", "focus handler count anchor changed");
  writeFileSync(uiPath, ui);
}

let focusMarkupContract = readFileSync(markupContractPath, "utf8");
if (!focusMarkupContract.includes('std.mem.eql(u8, event, "focus") and !markup.blurEventElement')) {
  const anchor = `        if (std.mem.eql(u8, event, "blur") and !markup.blurEventElement(node.name)) {\n            return self.failAttr(node, attribute, markup.on_blur_element_message);\n        }\n        if (std.mem.eql(u8, event, "input")) {`;
  const replacement = `        if (std.mem.eql(u8, event, "blur") and !markup.blurEventElement(node.name)) {\n            return self.failAttr(node, attribute, markup.on_blur_element_message);\n        }\n        if (std.mem.eql(u8, event, "focus") and !markup.blurEventElement(node.name)) {\n            return self.failAttr(node, attribute, markup.on_focus_element_message);\n        }\n        if (std.mem.eql(u8, event, "input")) {`;
  focusMarkupContract = replaceOnce(focusMarkupContract, anchor, replacement, "focus contract anchor changed");
  writeFileSync(markupContractPath, focusMarkupContract);
}

let focusMarkupCompiled = readFileSync(markupCompiledPath, "utf8");
if (!focusMarkupCompiled.includes('event, "focus"')) {
  const anchor = `            if (comptime std.mem.eql(u8, event, "blur")) {\n                comptime {\n                    if (!markup.blurEventElement(node.name)) fail(node, markup.on_blur_element_message);\n                }\n            }\n            if (comptime std.mem.eql(u8, event, "scroll")) {`;
  const replacement = `            if (comptime std.mem.eql(u8, event, "blur")) {\n                comptime {\n                    if (!markup.blurEventElement(node.name)) fail(node, markup.on_blur_element_message);\n                }\n            }\n            if (comptime std.mem.eql(u8, event, "focus")) {\n                comptime {\n                    if (!markup.blurEventElement(node.name)) fail(node, markup.on_focus_element_message);\n                }\n            }\n            if (comptime std.mem.eql(u8, event, "scroll")) {`;
  focusMarkupCompiled = replaceOnce(focusMarkupCompiled, anchor, replacement, "compiled focus decoder anchor changed");
  focusMarkupCompiled = replaceOnce(focusMarkupCompiled, `            } else if (comptime std.mem.eql(u8, event, "blur")) {\n                options.on_blur = msg;\n            } else if (comptime std.mem.eql(u8, event, "submit")) {`, `            } else if (comptime std.mem.eql(u8, event, "blur")) {\n                options.on_blur = msg;\n            } else if (comptime std.mem.eql(u8, event, "focus")) {\n                options.on_focus = msg;\n            } else if (comptime std.mem.eql(u8, event, "submit")) {`, "compiled focus handler anchor changed");
  writeFileSync(markupCompiledPath, focusMarkupCompiled);
}

let focusMarkupView = readFileSync(markupViewPath, "utf8");
if (!focusMarkupView.includes('event, "focus"')) {
  const anchor = `            if (std.mem.eql(u8, event, "blur") and !markup.blurEventElement(node.name)) {\n                return self.failVoid(node, markup.on_blur_element_message);\n            }\n            if (std.mem.eql(u8, event, "scroll")) {`;
  const replacement = `            if (std.mem.eql(u8, event, "blur") and !markup.blurEventElement(node.name)) {\n                return self.failVoid(node, markup.on_blur_element_message);\n            }\n            if (std.mem.eql(u8, event, "focus") and !markup.blurEventElement(node.name)) {\n                return self.failVoid(node, markup.on_focus_element_message);\n            }\n            if (std.mem.eql(u8, event, "scroll")) {`;
  focusMarkupView = replaceOnce(focusMarkupView, anchor, replacement, "runtime focus decoder anchor changed");
  focusMarkupView = replaceOnce(focusMarkupView, `            } else if (std.mem.eql(u8, event, "blur")) {\n                options.on_blur = msg;\n            } else if (std.mem.eql(u8, event, "submit")) {`, `            } else if (std.mem.eql(u8, event, "blur")) {\n                options.on_blur = msg;\n            } else if (std.mem.eql(u8, event, "focus")) {\n                options.on_focus = msg;\n            } else if (std.mem.eql(u8, event, "submit")) {`, "runtime focus handler anchor changed");
  writeFileSync(markupViewPath, focusMarkupView);
}

let focusRuntimeApi = readFileSync(runtimeApiPath, "utf8");
if (!focusRuntimeApi.includes("focused_id: canvas.ObjectId = 0")) {
  focusRuntimeApi = replaceOnce(focusRuntimeApi, `    blurred_id: canvas.ObjectId = 0,\n};\n\npub const CanvasWidgetKeyboardEvent = struct {`, `    blurred_id: canvas.ObjectId = 0,\n    /// The editable text widget that gained canvas focus before this pointer event was dispatched.\n    /// 0 means focus was unchanged, the new target was not text-entry, or this was not a focus gesture.\n    focused_id: canvas.ObjectId = 0,\n};\n\npub const CanvasWidgetKeyboardEvent = struct {`, "pointer focus payload anchor changed");
  focusRuntimeApi = replaceOnce(focusRuntimeApi, `    blurred_id: canvas.ObjectId = 0,\n    /// True when this event is dispatched OUTSIDE a gpu-surface input`, `    blurred_id: canvas.ObjectId = 0,\n    /// The editable text widget that gained canvas focus before this keyboard event was routed.\n    focused_id: canvas.ObjectId = 0,\n    /// True when this event is dispatched OUTSIDE a gpu-surface input`, "keyboard focus payload anchor changed");
  writeFileSync(runtimeApiPath, focusRuntimeApi);
}

let focusCanvasEvents = readFileSync(eventsPath, "utf8");
if (!focusCanvasEvents.includes("FocusTransition = struct")) {
  const transitionAnchor = "pub fn RuntimeCanvasWidgetEvents(comptime Runtime: type) type {\n    return struct {";
  const transitionReplacement = `pub fn RuntimeCanvasWidgetEvents(comptime Runtime: type) type {\n    return struct {\n        const FocusTransition = struct {\n            blurred_id: canvas.ObjectId = 0,\n            focused_id: canvas.ObjectId = 0,\n        };`;
  focusCanvasEvents = replaceOnce(focusCanvasEvents, transitionAnchor, transitionReplacement, "focus transition type anchor changed");
  focusCanvasEvents = replaceOnce(focusCanvasEvents, `        /// Returns the old focused id only when an editable text widget lost\n        /// focus through this real pointer-down transition. Unmount, window\n        /// deactivation, and programmatic focus remain deliberately outside\n        /// the on-blur contract.\n        pub fn updateCanvasWidgetFocusFromPointer(self: *Runtime, pointer_event: CanvasWidgetPointerEvent) anyerror!canvas.ObjectId {\n            if (pointer_event.pointer.phase != .down) return 0;\n            const index = runtimeFindViewIndex(self, pointer_event.window_id, pointer_event.view_label) orelse return 0;\n            if (self.views[index].kind != .gpu_surface) return 0;`, `        /// Reports only editable text controls crossed by a real pointer-down\n        /// focus transition. Unmount, window deactivation, and programmatic\n        /// focus deliberately remain outside the blur/focus event contract.\n        pub fn updateCanvasWidgetFocusFromPointer(self: *Runtime, pointer_event: CanvasWidgetPointerEvent) anyerror!FocusTransition {\n            if (pointer_event.pointer.phase != .down) return .{};\n            const index = runtimeFindViewIndex(self, pointer_event.window_id, pointer_event.view_label) orelse return .{};\n            if (self.views[index].kind != .gpu_surface) return .{};`, "pointer focus transition signature anchor changed");
  focusCanvasEvents = replaceOnce(focusCanvasEvents, `            if (previous_focus_id == next_focus_id and self.views[index].canvas_widget_focus_visible_id == next_focus_visible_id) return 0;\n            var blurred_id: canvas.ObjectId = 0;`, `            if (previous_focus_id == next_focus_id and self.views[index].canvas_widget_focus_visible_id == next_focus_visible_id) return .{};\n            var transition: FocusTransition = .{};`, "pointer focus transition state anchor changed");
  focusCanvasEvents = replaceOnce(focusCanvasEvents, `                        blurred_id = previous_focus_id;`, `                        transition.blurred_id = previous_focus_id;`, "pointer focus blur assignment anchor changed");
  focusCanvasEvents = replaceOnce(focusCanvasEvents, `            const previous_state = self.views[index].canvasWidgetRenderState();\n            self.views[index].canvas_widget_focused_id = next_focus_id;`, `            if (next_focus_id != 0) {\n                if (self.views[index].widgetLayoutTree().focusTargetById(next_focus_id)) |next| {\n                    if (canvas_widget_runtime.canvasWidgetEditableTextKind(next.kind)) {\n                        transition.focused_id = next_focus_id;\n                    }\n                }\n            }\n            const previous_state = self.views[index].canvasWidgetRenderState();\n            self.views[index].canvas_widget_focused_id = next_focus_id;`, "pointer focus arrival assignment anchor changed");
  focusCanvasEvents = replaceOnce(focusCanvasEvents, `            try invalidateForCanvasWidgetRenderStateChange(self, index, previous_state, self.views[index].canvasWidgetRenderState());\n            return blurred_id;`, `            try invalidateForCanvasWidgetRenderStateChange(self, index, previous_state, self.views[index].canvasWidgetRenderState());\n            return transition;`, "pointer focus transition return anchor changed");
  focusCanvasEvents = replaceOnce(focusCanvasEvents, `        pub fn updateCanvasWidgetFocusFromKeyboardInput(self: *Runtime, input_event: GpuSurfaceInputEvent, blurred_id: *canvas.ObjectId) anyerror!bool {\n            blurred_id.* = 0;`, `        pub fn updateCanvasWidgetFocusFromKeyboardInput(self: *Runtime, input_event: GpuSurfaceInputEvent, blurred_id: *canvas.ObjectId, focused_id: *canvas.ObjectId) anyerror!bool {\n            blurred_id.* = 0;\n            focused_id.* = 0;`, "keyboard focus transition signature anchor changed");
  focusCanvasEvents = focusCanvasEvents.replaceAll("entry_id,\n                            blurred_id,", "entry_id,\n                            blurred_id,\n                            focused_out,");
  focusCanvasEvents = focusCanvasEvents.replaceAll("target.id, blurred_id)", "target.id, blurred_id, focused_out)");
  focusCanvasEvents = replaceOnce(focusCanvasEvents, `            target_id: canvas.ObjectId,\n            blurred_id: *canvas.ObjectId,\n        ) anyerror!bool {\n            try setCanvasWidgetFocusFromKeyboard(self, view_index, target_id);`, `            target_id: canvas.ObjectId,\n            blurred_id: *canvas.ObjectId,\n            focused_id: *canvas.ObjectId,\n        ) anyerror!bool {\n            try setCanvasWidgetFocusFromKeyboard(self, view_index, target_id);`, "keyboard focus moved helper signature anchor changed");
  focusCanvasEvents = replaceOnce(focusCanvasEvents, `            if (moved and previous != 0 and !moved_into_owned_combobox_menu) {\n                if (self.views[view_index].widgetLayoutTree().focusTargetById(previous)) |old_target| {\n                    if (canvas_widget_runtime.canvasWidgetEditableTextKind(old_target.kind)) {\n                        blurred_id.* = previous;\n                    }\n                }\n            }\n            return moved;`, `            if (moved and previous != 0 and !moved_into_owned_combobox_menu) {\n                if (self.views[view_index].widgetLayoutTree().focusTargetById(previous)) |old_target| {\n                    if (canvas_widget_runtime.canvasWidgetEditableTextKind(old_target.kind)) {\n                        blurred_id.* = previous;\n                    }\n                }\n            }\n            if (moved and !moved_into_owned_combobox_menu) {\n                if (self.views[view_index].widgetLayoutTree().focusTargetById(target_id)) |next_target| {\n                    if (canvas_widget_runtime.canvasWidgetEditableTextKind(next_target.kind)) {\n                        focused_id.* = target_id;\n                    }\n                }\n            }\n            return moved;`, "keyboard focus arrival assignment anchor changed");
  writeFileSync(eventsPath, focusCanvasEvents);
}

let focusGpuSurfaceEvents = readFileSync(gpuSurfaceEventsPath, "utf8");
if (!focusGpuSurfaceEvents.includes("pointer_event.focused_id = transition.focused_id")) {
  focusGpuSurfaceEvents = replaceOnce(focusGpuSurfaceEvents, "                    pointer_event.blurred_id = try CanvasWidgetEventMethods().updateCanvasWidgetFocusFromPointer(self, pointer_event.*);", "                    const transition = try CanvasWidgetEventMethods().updateCanvasWidgetFocusFromPointer(self, pointer_event.*);\n                    pointer_event.blurred_id = transition.blurred_id;\n                    pointer_event.focused_id = transition.focused_id;", "pointer focus event plumbing anchor changed");
  focusGpuSurfaceEvents = replaceOnce(focusGpuSurfaceEvents, "            var widget_blurred_id: canvas.ObjectId = 0;\n            const widget_focus_moved = if (widget_surface_dismissed or targetless_composition_owns_keys or terminal_key_lifetime_suppressed)\n                false\n            else\n                try CanvasWidgetEventMethods().updateCanvasWidgetFocusFromKeyboardInput(self, input_event, &widget_blurred_id);", "            var widget_blurred_id: canvas.ObjectId = 0;\n            var widget_focused_id: canvas.ObjectId = 0;\n            const widget_focus_moved = if (widget_surface_dismissed or targetless_composition_owns_keys or terminal_key_lifetime_suppressed)\n                false\n            else\n                try CanvasWidgetEventMethods().updateCanvasWidgetFocusFromKeyboardInput(self, input_event, &widget_blurred_id, &widget_focused_id);", "keyboard focus event plumbing anchor changed");
  focusGpuSurfaceEvents = replaceOnce(focusGpuSurfaceEvents, "                keyboard_event.keyboard.focus_moved = widget_focus_moved;\n                keyboard_event.blurred_id = widget_blurred_id;", "                keyboard_event.keyboard.focus_moved = widget_focus_moved;\n                keyboard_event.blurred_id = widget_blurred_id;\n                keyboard_event.focused_id = widget_focused_id;", "keyboard focus assignment anchor changed");
  writeFileSync(gpuSurfaceEventsPath, focusGpuSurfaceEvents);
}

let focusUiApp = readFileSync(uiAppPath, "utf8");
if (!focusUiApp.includes("pointer_event.focused_id")) {
  focusUiApp = replaceOnce(focusUiApp, `            if (pointer_event.blurred_id != 0) {\n                if (tree.msgFor(pointer_event.blurred_id, .blur)) |msg| {\n                    try self.dispatch(runtime, pointer_event.window_id, msg);\n                }\n            }\n            const terminal_selected`, `            if (pointer_event.blurred_id != 0) {\n                if (tree.msgFor(pointer_event.blurred_id, .blur)) |msg| {\n                    try self.dispatch(runtime, pointer_event.window_id, msg);\n                }\n            }\n            if (pointer_event.focused_id != 0) {\n                if (tree.msgFor(pointer_event.focused_id, .focus)) |msg| {\n                    try self.dispatch(runtime, pointer_event.window_id, msg);\n                }\n            }\n            const terminal_selected`, "ui-app pointer focus dispatch anchor changed");
  focusUiApp = replaceOnce(focusUiApp, `            if (keyboard_event.blurred_id != 0) {\n                if (tree.msgFor(keyboard_event.blurred_id, .blur)) |msg| {\n                    try self.dispatch(runtime, keyboard_event.window_id, msg);\n                }\n            }\n            // Key precedence`, `            if (keyboard_event.blurred_id != 0) {\n                if (tree.msgFor(keyboard_event.blurred_id, .blur)) |msg| {\n                    try self.dispatch(runtime, keyboard_event.window_id, msg);\n                }\n            }\n            if (keyboard_event.focused_id != 0) {\n                if (tree.msgFor(keyboard_event.focused_id, .focus)) |msg| {\n                    try self.dispatch(runtime, keyboard_event.window_id, msg);\n                }\n            }\n            // Key precedence`, "ui-app keyboard focus dispatch anchor changed");
  writeFileSync(uiAppPath, focusUiApp);
}

// Secondary-button input is consumed before the normal pointer pipeline, but
// the default editable/terminal context menus deliberately move focus so Cut,
// Copy, and Paste act on the field under the pointer. Carry that real focus
// transition through its own event: synthesizing a primary pointer event here
// would also run press/on-hold behavior and violate context-menu precedence.
let focusContextRuntimeApi = readFileSync(runtimeApiPath, "utf8");
if (!focusContextRuntimeApi.includes("pub const CanvasWidgetFocusEvent")) {
  focusContextRuntimeApi = replaceOnce(
    focusContextRuntimeApi,
    `    focused_id: canvas.ObjectId = 0,\n};\n\npub const CanvasWidgetKeyboardEvent = struct {`,
    `    focused_id: canvas.ObjectId = 0,\n};\n\n/// A real focus transition performed by a consumed pointer path, such as a\n/// secondary click that opens the platform edit menu. It is separate from\n/// CanvasWidgetPointerEvent so context-menu input cannot also press or hold.\npub const CanvasWidgetFocusEvent = struct {\n    window_id: platform.WindowId = 1,\n    view_label: []const u8,\n    blurred_id: canvas.ObjectId = 0,\n    focused_id: canvas.ObjectId = 0,\n};\n\npub const CanvasWidgetKeyboardEvent = struct {`,
    "context-menu focus event type anchor changed",
  );
  focusContextRuntimeApi = replaceOnce(
    focusContextRuntimeApi,
    "    canvas_widget_pointer: CanvasWidgetPointerEvent,\n    canvas_widget_keyboard: CanvasWidgetKeyboardEvent,",
    "    canvas_widget_pointer: CanvasWidgetPointerEvent,\n    canvas_widget_focus: CanvasWidgetFocusEvent,\n    canvas_widget_keyboard: CanvasWidgetKeyboardEvent,",
    "context-menu focus event union anchor changed",
  );
  focusContextRuntimeApi = replaceOnce(
    focusContextRuntimeApi,
    '            .canvas_widget_pointer => "canvas_widget_pointer",\n            .canvas_widget_keyboard => "canvas_widget_keyboard",',
    '            .canvas_widget_pointer => "canvas_widget_pointer",\n            .canvas_widget_focus => "canvas_widget_focus",\n            .canvas_widget_keyboard => "canvas_widget_keyboard",',
    "context-menu focus event name anchor changed",
  );
  writeFileSync(runtimeApiPath, focusContextRuntimeApi);
}

let focusContextCore = readFileSync(corePath, "utf8");
if (!focusContextCore.includes("pub const CanvasWidgetFocusEvent")) {
  focusContextCore = replaceOnce(
    focusContextCore,
    "pub const CanvasWidgetPointerEvent = runtime_api.CanvasWidgetPointerEvent;\npub const CanvasWidgetKeyboardEvent = runtime_api.CanvasWidgetKeyboardEvent;",
    "pub const CanvasWidgetPointerEvent = runtime_api.CanvasWidgetPointerEvent;\npub const CanvasWidgetFocusEvent = runtime_api.CanvasWidgetFocusEvent;\npub const CanvasWidgetKeyboardEvent = runtime_api.CanvasWidgetKeyboardEvent;",
    "context-menu focus core export anchor changed",
  );
  writeFileSync(corePath, focusContextCore);
}

let focusContextFlow = readFileSync(flowPath, "utf8");
if (!focusContextFlow.includes(".canvas_widget_focus => {}")) {
  focusContextFlow = replaceOnce(
    focusContextFlow,
    "                .canvas_widget_pointer => {},\n                .canvas_widget_keyboard => {},",
    "                .canvas_widget_pointer => {},\n                .canvas_widget_focus => {},\n                .canvas_widget_keyboard => {},",
    "context-menu focus flow anchor changed",
  );
  writeFileSync(flowPath, focusContextFlow);
}

let focusContextMenu = readFileSync(contextMenuPath, "utf8");
if (!focusContextMenu.includes("dispatchCanvasWidgetFocusTransition")) {
  focusContextMenu = replaceOnce(
    focusContextMenu,
    `                    _ = try CanvasWidgetEventMethods().updateCanvasWidgetFocusFromPointer(self, pointer_event);\n                    const has_selection = if (canvas.widgetTextSelectionRange(widget)) |range| !range.isCollapsed(widget.text.len) else false;`,
    `                    const transition = try CanvasWidgetEventMethods().updateCanvasWidgetFocusFromPointer(self, pointer_event);\n                    var focus_view_label: [platform.max_view_label_bytes]u8 = undefined;\n                    const focus_view_label_len = @min(pointer_event.view_label.len, focus_view_label.len);\n                    @memcpy(focus_view_label[0..focus_view_label_len], pointer_event.view_label[0..focus_view_label_len]);\n                    const has_selection = if (canvas.widgetTextSelectionRange(widget)) |range| !range.isCollapsed(widget.text.len) else false;`,
    "editable context-menu focus capture anchor changed",
  );
  focusContextMenu = replaceOnce(
    focusContextMenu,
    `                    _ = try showMenu(self, app, index, .{\n                        .window_id = input_event.window_id,\n                        .target_id = target.id,\n                        .kind = .edit_text,\n                    }, point, items[0..5]);\n                    return;`,
    `                    _ = try showMenu(self, app, index, .{\n                        .window_id = input_event.window_id,\n                        .target_id = target.id,\n                        .kind = .edit_text,\n                    }, point, items[0..5]);\n                    try dispatchCanvasWidgetFocusTransition(\n                        self,\n                        app,\n                        pointer_event.window_id,\n                        focus_view_label[0..focus_view_label_len],\n                        transition.blurred_id,\n                        transition.focused_id,\n                    );\n                    return;`,
    "editable context-menu focus dispatch anchor changed",
  );
  focusContextMenu = replaceOnce(
    focusContextMenu,
    `                    _ = try CanvasWidgetEventMethods().updateCanvasWidgetFocusFromPointer(self, pointer_event);\n                    const has_selection = if (widget.terminal.grid) |grid| grid.selection_active else false;`,
    `                    const transition = try CanvasWidgetEventMethods().updateCanvasWidgetFocusFromPointer(self, pointer_event);\n                    var focus_view_label: [platform.max_view_label_bytes]u8 = undefined;\n                    const focus_view_label_len = @min(pointer_event.view_label.len, focus_view_label.len);\n                    @memcpy(focus_view_label[0..focus_view_label_len], pointer_event.view_label[0..focus_view_label_len]);\n                    const has_selection = if (widget.terminal.grid) |grid| grid.selection_active else false;`,
    "terminal context-menu focus capture anchor changed",
  );
  focusContextMenu = replaceOnce(
    focusContextMenu,
    `                    _ = try showMenu(self, app, index, .{\n                        .window_id = input_event.window_id,\n                        .target_id = target.id,\n                        .kind = .terminal,\n                    }, point, items[0..2]);\n                    return;`,
    `                    _ = try showMenu(self, app, index, .{\n                        .window_id = input_event.window_id,\n                        .target_id = target.id,\n                        .kind = .terminal,\n                    }, point, items[0..2]);\n                    try dispatchCanvasWidgetFocusTransition(\n                        self,\n                        app,\n                        pointer_event.window_id,\n                        focus_view_label[0..focus_view_label_len],\n                        transition.blurred_id,\n                        transition.focused_id,\n                    );\n                    return;`,
    "terminal context-menu focus dispatch anchor changed",
  );
  focusContextMenu = replaceOnce(
    focusContextMenu,
    `        fn CanvasWidgetEventMethods() type {\n            return runtime_canvas_widget_events.RuntimeCanvasWidgetEvents(Runtime);\n        }`,
    `        fn dispatchCanvasWidgetFocusTransition(\n            self: *Runtime,\n            app: runtime_api.App(Runtime),\n            window_id: platform.WindowId,\n            view_label: []const u8,\n            blurred_id: canvas.ObjectId,\n            focused_id: canvas.ObjectId,\n        ) anyerror!void {\n            if (blurred_id == 0 and focused_id == 0) return;\n            try self.dispatchEvent(app, .{ .canvas_widget_focus = .{\n                .window_id = window_id,\n                .view_label = view_label,\n                .blurred_id = blurred_id,\n                .focused_id = focused_id,\n            } });\n        }\n\n        fn CanvasWidgetEventMethods() type {\n            return runtime_canvas_widget_events.RuntimeCanvasWidgetEvents(Runtime);\n        }`,
    "context-menu focus dispatch helper anchor changed",
  );
  writeFileSync(contextMenuPath, focusContextMenu);
}

let focusContextUiApp = readFileSync(uiAppPath, "utf8");
if (!focusContextUiApp.includes("fn handleFocusTransition")) {
  focusContextUiApp = replaceOnce(
    focusContextUiApp,
    "                .canvas_widget_pointer => |pointer_event| try self.handlePointer(runtime, pointer_event),\n                .canvas_widget_keyboard => |keyboard_event| try self.handleKeyboard(runtime, keyboard_event),",
    "                .canvas_widget_pointer => |pointer_event| try self.handlePointer(runtime, pointer_event),\n                .canvas_widget_focus => |focus_event| try self.handleFocusTransition(runtime, focus_event),\n                .canvas_widget_keyboard => |keyboard_event| try self.handleKeyboard(runtime, keyboard_event),",
    "context-menu focus ui-app routing anchor changed",
  );
  focusContextUiApp = replaceOnce(
    focusContextUiApp,
    `                .canvas_widget_pointer,\n                .canvas_widget_drag,`,
    `                .canvas_widget_pointer,\n                .canvas_widget_focus,\n                .canvas_widget_drag,`,
    "context-menu focus hover-drain anchor changed",
  );
  focusContextUiApp = replaceOnce(
    focusContextUiApp,
    `        /// Typed press dispatch resolves through the press target — the\n        /// deepest widget on the hit path that claims presses — so a press`,
    `        /// Dispatch a focus-only transition from a consumed pointer path.\n        /// Re-resolve the tree after blur because that Msg may rebuild the view\n        /// before the new field's focus handler is looked up.\n        fn handleFocusTransition(self: *Self, runtime: *Runtime, focus_event: core.CanvasWidgetFocusEvent) anyerror!void {\n            if (focus_event.blurred_id != 0) {\n                if (self.treeForViewLabel(focus_event.view_label)) |tree| {\n                    if (tree.msgFor(focus_event.blurred_id, .blur)) |msg| {\n                        try self.dispatch(runtime, focus_event.window_id, msg);\n                    }\n                }\n            }\n            if (focus_event.focused_id != 0) {\n                if (self.treeForViewLabel(focus_event.view_label)) |tree| {\n                    if (tree.msgFor(focus_event.focused_id, .focus)) |msg| {\n                        try self.dispatch(runtime, focus_event.window_id, msg);\n                    }\n                }\n            }\n        }\n\n        /// Typed press dispatch resolves through the press target — the\n        /// deepest widget on the hit path that claims presses — so a press`,
    "context-menu focus ui-app handler anchor changed",
  );
  writeFileSync(uiAppPath, focusContextUiApp);
}

// Keep this generic regression beside the existing combobox fixture. It
// proves the public on-focus contract rather than a Tax Profile-specific
// presentation policy: automation focus is silent, real Tab/pointer moves
// dispatch blur before focus, re-clicking the focused field is silent, and
// entering a combobox-owned menu remains an internal transition.
let focusUiAppTests = readFileSync(uiAppTestsPath, "utf8");
if (!focusUiAppTests.includes("text-entry on-focus dispatches after blur on real transitions")) {
  focusUiAppTests = replaceOnce(focusUiAppTests, "    blur_count: u32 = 0,\n};", "    blur_count: u32 = 0,\n    focus_count: u32 = 0,\n    focus_after_blur: bool = false,\n};", "focus test model anchor changed");
  focusUiAppTests = replaceOnce(focusUiAppTests, "    blurred,\n};", "    blurred,\n    focused,\n};", "focus test message anchor changed");
  focusUiAppTests = replaceOnce(focusUiAppTests, "        .blurred => model.blur_count += 1,\n    }", "        .blurred => model.blur_count += 1,\n        .focused => {\n            model.focus_count += 1;\n            model.focus_after_blur = model.blur_count > 0;\n        },\n    }", "focus test update anchor changed");
  focusUiAppTests = replaceOnce(focusUiAppTests, "        .on_blur = .blurred,\n    }, .{});", "        .on_blur = .blurred,\n        .on_focus = .focused,\n    }, .{});", "combobox focus binding anchor changed");
  focusUiAppTests = replaceOnce(focusUiAppTests, "            .on_blur = .blurred,\n        }, .{}),", "            .on_blur = .blurred,\n            .on_focus = .focused,\n        }, .{}),", "text-field focus binding anchor changed");
  const regression = `test "text-entry on-focus dispatches after blur on real transitions" {
    const harness = try core.TestHarness().create(std.testing.allocator, .{
        .size = geometry.SizeF.init(400, 300),
    });
    defer harness.destroy(std.testing.allocator);
    harness.null_platform.gpu_surfaces = true;

    const app_state = try std.testing.allocator.create(ComboMirrorApp);
    defer std.testing.allocator.destroy(app_state);
    app_state.* = ComboMirrorApp.init(std.heap.page_allocator, .{}, .{
        .name = "ui-app-text-entry-focus",
        .scene = combo_mirror_scene,
        .canvas_label = combo_mirror_canvas_label,
        .update = comboMirrorUpdate,
        .view = comboMirrorView,
    });
    defer app_state.deinit();
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
    const note_id = findWidgetIdByKind(app_state.tree.?.root, .text_field).?;
    // Programmatic / automation focus remains outside the user-event contract.
    try core.testing.dispatchAutomationWidgetAction(&harness.runtime, app, .{
        .view_label = combo_mirror_canvas_label,
        .id = combo_id,
        .action = .focus,
    });
    try std.testing.expectEqual(@as(u32, 0), app_state.model.focus_count);

    try comboMirrorKey(harness, app, "tab");
    try std.testing.expectEqual(note_id, harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expectEqual(@as(u32, 1), app_state.model.blur_count);
    try std.testing.expectEqual(@as(u32, 1), app_state.model.focus_count);
    try std.testing.expect(app_state.model.focus_after_blur);

    const note_frame = (try harness.runtime.canvasWidgetLayout(1, combo_mirror_canvas_label)).findById(note_id).?.frame;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = combo_mirror_canvas_label,
        .kind = .pointer_down,
        .x = note_frame.x + 4,
        .y = note_frame.y + note_frame.height * 0.5,
        .timestamp_ns = 2_000_000,
    } });
    try std.testing.expectEqual(@as(u32, 1), app_state.model.focus_count);

    const combo_frame = (try harness.runtime.canvasWidgetLayout(1, combo_mirror_canvas_label)).findById(combo_id).?.frame;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = combo_mirror_canvas_label,
        .kind = .pointer_down,
        .x = combo_frame.x + 4,
        .y = combo_frame.y + combo_frame.height * 0.5,
        .timestamp_ns = 3_000_000,
    } });
    try std.testing.expectEqual(@as(u32, 2), app_state.model.blur_count);
    try std.testing.expectEqual(@as(u32, 2), app_state.model.focus_count);

    // Tab into the owned result menu is not field departure/arrival.
    try comboMirrorKey(harness, app, "arrowdown");
    try std.testing.expect(app_state.model.open);
    try comboMirrorKey(harness, app, "tab");
    try std.testing.expectEqual(@as(u32, 2), app_state.model.blur_count);
    try std.testing.expectEqual(@as(u32, 2), app_state.model.focus_count);
}

`;
  const anchor = 'test "a closed combobox\'s open arrows move neither the retained caret nor the model mirror" {';
  focusUiAppTests = replaceOnce(focusUiAppTests, anchor, `${regression}${anchor}`, "focus regression test anchor changed");
  writeFileSync(uiAppTestsPath, focusUiAppTests);
}

focusUiAppTests = readFileSync(uiAppTestsPath, "utf8");
if (!focusUiAppTests.includes("right-click focus transitions dispatch blur then focus")) {
  const contextFocusRegression = `test "right-click focus transitions dispatch blur then focus" {\n    const harness = try core.TestHarness().create(std.testing.allocator, .{\n        .size = geometry.SizeF.init(400, 300),\n    });\n    defer harness.destroy(std.testing.allocator);\n    harness.null_platform.gpu_surfaces = true;\n\n    const app_state = try std.testing.allocator.create(ComboMirrorApp);\n    defer std.testing.allocator.destroy(app_state);\n    app_state.* = ComboMirrorApp.init(std.heap.page_allocator, .{}, .{\n        .name = "ui-app-context-focus",\n        .scene = combo_mirror_scene,\n        .canvas_label = combo_mirror_canvas_label,\n        .update = comboMirrorUpdate,\n        .view = comboMirrorView,\n    });\n    defer app_state.deinit();\n    const app = app_state.app();\n    try harness.start(app);\n    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_frame = .{\n        .label = combo_mirror_canvas_label,\n        .size = geometry.SizeF.init(400, 300),\n        .scale_factor = 1,\n        .frame_index = 1,\n        .timestamp_ns = 1_000_000,\n        .nonblank = true,\n    } });\n\n    const combo_id = findWidgetIdByKind(app_state.tree.?.root, .combobox).?;\n    const note_id = findWidgetIdByKind(app_state.tree.?.root, .text_field).?;\n    try core.testing.dispatchAutomationWidgetAction(&harness.runtime, app, .{\n        .view_label = combo_mirror_canvas_label,\n        .id = combo_id,\n        .action = .focus,\n    });\n    try std.testing.expectEqual(@as(u32, 0), app_state.model.blur_count);\n    try std.testing.expectEqual(@as(u32, 0), app_state.model.focus_count);\n\n    const note_frame = (try harness.runtime.canvasWidgetLayout(1, combo_mirror_canvas_label)).findById(note_id).?.frame;\n    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{\n        .window_id = 1,\n        .label = combo_mirror_canvas_label,\n        .kind = .pointer_down,\n        .button = 1,\n        .x = note_frame.x + 4,\n        .y = note_frame.y + note_frame.height * 0.5,\n        .timestamp_ns = 2_000_000,\n    } });\n\n    try std.testing.expectEqual(note_id, harness.runtime.views[0].canvas_widget_focused_id);\n    try std.testing.expectEqual(@as(u32, 1), app_state.model.blur_count);\n    try std.testing.expectEqual(@as(u32, 1), app_state.model.focus_count);\n    try std.testing.expect(app_state.model.focus_after_blur);\n    try std.testing.expectEqual(@as(usize, 1), harness.null_platform.context_menu_request_count);\n}\n\n`;
  const anchor = 'test "a closed combobox\'s open arrows move neither the retained caret nor the model mirror" {';
  focusUiAppTests = replaceOnce(
    focusUiAppTests,
    anchor,
    `${contextFocusRegression}${anchor}`,
    "context-menu focus regression test anchor changed",
  );
  writeFileSync(uiAppTestsPath, focusUiAppTests);
}
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
// The focus layer below evolves the pointer helper's return type, so its
// signature cannot be the baseline-install sentinel. The blur contract
// comment is introduced exactly by this block and remains true after later
// additive layers have been installed.
if (!canvasEvents.includes("blur/focus event contract.")) {
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
// The focus transition layer below supersedes the blur assignment. Treat
// either form as installed so a second postinstall is a no-op.
if (!gpuSurfaceEvents.includes("pointer_event.blurred_id = try CanvasWidgetEventMethods().updateCanvasWidgetFocusFromPointer") &&
    !gpuSurfaceEvents.includes("pointer_event.focused_id = transition.focused_id")) {
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

// The focus layer depends on every blur/combobox baseline seam above. Running
// it here makes a fresh 0.6.1 postinstall deterministic and keeps a later
// SDK anchor change fail-closed rather than silently creating half an event.
applyFocusPatch();

// `updateCanvasWidgetFocusFromKeyboardInput` already has a local
// `focused_id` later in its key-routing branch. Keep the event out-parameter
// distinct so the generated Zig does not shadow it (and so the patch works
// against both a cold SDK install and an earlier partially patched install).
function repairKeyboardFocusOutParameter() {
  let source = readFileSync(eventsPath, "utf8");
  const start = "        pub fn updateCanvasWidgetFocusFromKeyboardInput(";
  const end = "\n        fn setCanvasWidgetFocusFromKeyboardMoved(";
  const startIndex = source.indexOf(start);
  if (startIndex < 0) {
    throw new Error("Unable to apply Native SDK combobox patch: keyboard focus function missing.");
  }
  const endIndex = source.indexOf(end, startIndex);
  if (endIndex < 0) {
    throw new Error("Unable to apply Native SDK combobox patch: keyboard focus helper boundary changed.");
  }
  let body = source.slice(startIndex, endIndex);
  if (body.includes("focused_id: *canvas.ObjectId")) {
    body = body.replace(
      "focused_id: *canvas.ObjectId",
      "focused_out: *canvas.ObjectId",
    );
    body = body.replace("focused_id.* = 0", "focused_out.* = 0");
    body = body.replaceAll(
      "entry_id,\n                            blurred_id,\n                            focused_id,",
      "entry_id,\n                            blurred_id,\n                            focused_out,",
    );
    body = body.replaceAll(
      "target.id, blurred_id, focused_id)",
      "target.id, blurred_id, focused_out)",
    );
  }
  body = body.replaceAll(
    "entry_id, blurred_id)",
    "entry_id, blurred_id, focused_out)",
  );
  source = `${source.slice(0, startIndex)}${body}${source.slice(endIndex)}`;
  writeFileSync(eventsPath, source);
}
repairKeyboardFocusOutParameter();

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

// A combobox trigger and the result menu it owns are one logical text-entry
// control. Pointer focus still moves onto a menu row for keyboard activation,
// but that internal move must not emit the trigger's blur before pointer-up
// can select the row.
let finalViewTree = readFileSync(viewTreePath, "utf8");
if (!finalViewTree.includes("canvasWidgetFocusMovesIntoOwnedComboboxMenu")) {
  const helper = `    /// Whether focus moves from one specific combobox trigger into the
    /// anchored result menu that trigger owns. Physical focus still moves to
    /// the row, but the public text-entry lifecycle remains inside one control.
    pub fn canvasWidgetFocusMovesIntoOwnedComboboxMenu(
        self: *const RuntimeView,
        trigger_id: canvas.ObjectId,
        target_id: canvas.ObjectId,
    ) bool {
        const trigger_index = self.canvasWidgetNodeIndexById(trigger_id) orelse
            return false;
        if (self.widget_layout_nodes[trigger_index].widget.kind != .combobox)
            return false;
        const surface_index = self.canvasWidgetOwnedMenuSurfaceIndex(
            trigger_index,
        ) orelse return false;
        return self.canvasWidgetIdDescendsFromIndex(target_id, surface_index);
    }

`;
  const anchor =
    "    /// Whether keyboard focus is on an entry inside a combobox-owned result\n";
  finalViewTree = replaceOnce(
    finalViewTree,
    anchor,
    `${helper}${anchor}`,
    "owned combobox pointer focus helper anchor changed",
  );
  writeFileSync(viewTreePath, finalViewTree);
}

let finalView = readFileSync(viewPath, "utf8");
if (!finalView.includes("canvasWidgetFocusMovesIntoOwnedComboboxMenu")) {
  const anchor =
    "    pub const canvasWidgetOwnedComboboxMenuEntryId = CanvasWidgetTreeMethods.canvasWidgetOwnedComboboxMenuEntryId;\n";
  const exportLine =
    "    pub const canvasWidgetFocusMovesIntoOwnedComboboxMenu = CanvasWidgetTreeMethods.canvasWidgetFocusMovesIntoOwnedComboboxMenu;\n";
  finalView = replaceOnce(
    finalView,
    anchor,
    `${anchor}${exportLine}`,
    "owned combobox pointer focus export anchor changed",
  );
  writeFileSync(viewPath, finalView);
}

let finalCanvasEvents = readFileSync(eventsPath, "utf8");
if (
  !finalCanvasEvents.includes(
    "A combobox-owned menu row is an internal focus transition",
  )
) {
  const anchor = `            var transition: FocusTransition = .{};
            if (previous_focus_id != 0 and previous_focus_id != next_focus_id) {
                if (self.views[index].widgetLayoutTree().focusTargetById(previous_focus_id)) |previous| {
                    if (canvas_widget_runtime.canvasWidgetEditableTextKind(previous.kind)) {
                        transition.blurred_id = previous_focus_id;
                    }
                }
            }
            if (next_focus_id != 0) {
                if (self.views[index].widgetLayoutTree().focusTargetById(next_focus_id)) |next| {
                    if (canvas_widget_runtime.canvasWidgetEditableTextKind(next.kind)) {
                        transition.focused_id = next_focus_id;
                    }
                }
            }
            const previous_state = self.views[index].canvasWidgetRenderState();`;
  const replacement = `            var transition: FocusTransition = .{};
            // A combobox-owned menu row is an internal focus transition:
            // keep physical row focus without blurring/refocusing the logical
            // text-entry control before pointer-up commits the option.
            const moved_into_owned_combobox_menu = previous_focus_id != 0 and
                next_focus_id != 0 and
                self.views[index].canvasWidgetFocusMovesIntoOwnedComboboxMenu(
                    previous_focus_id,
                    next_focus_id,
                );
            if (!moved_into_owned_combobox_menu) {
                if (previous_focus_id != 0 and previous_focus_id != next_focus_id) {
                    if (self.views[index].widgetLayoutTree().focusTargetById(previous_focus_id)) |previous| {
                        if (canvas_widget_runtime.canvasWidgetEditableTextKind(previous.kind)) {
                            transition.blurred_id = previous_focus_id;
                        }
                    }
                }
                if (next_focus_id != 0) {
                    if (self.views[index].widgetLayoutTree().focusTargetById(next_focus_id)) |next| {
                        if (canvas_widget_runtime.canvasWidgetEditableTextKind(next.kind)) {
                            transition.focused_id = next_focus_id;
                        }
                    }
                }
            }
            const previous_state = self.views[index].canvasWidgetRenderState();`;
  finalCanvasEvents = replaceOnce(
    finalCanvasEvents,
    anchor,
    replacement,
    "owned combobox pointer focus transition anchor changed",
  );
  writeFileSync(eventsPath, finalCanvasEvents);
}

// Blur and focus handlers can rebuild the retained tree. Resolve each phase
// independently, then acquire the post-focus tree used by the remainder of the
// pointer or keyboard event so no stale handler table survives a dispatch.
let finalUiApp = readFileSync(uiAppPath, "utf8");
if (!finalUiApp.includes("Normal pointer focus follows the re-resolving path")) {
  const pointerAnchor = `        fn handlePointer(self: *Self, runtime: *Runtime, pointer_event: core.CanvasWidgetPointerEvent) anyerror!void {
            const tree = self.treeForViewLabel(pointer_event.view_label) orelse return;
            // Focus changes before pointer activation. Dispatch the old text
            // field's commit/normalization message before the new target's
            // edit or press, matching the desktop blur-before-click order.
            if (pointer_event.blurred_id != 0) {
                if (tree.msgFor(pointer_event.blurred_id, .blur)) |msg| {
                    try self.dispatch(runtime, pointer_event.window_id, msg);
                }
            }
            if (pointer_event.focused_id != 0) {
                if (tree.msgFor(pointer_event.focused_id, .focus)) |msg| {
                    try self.dispatch(runtime, pointer_event.window_id, msg);
                }
            }
            const terminal_selected = try self.handleTerminalPointer(runtime, pointer_event);`;
  const pointerReplacement = `        fn handlePointer(self: *Self, runtime: *Runtime, pointer_event: core.CanvasWidgetPointerEvent) anyerror!void {
            // Normal pointer focus follows the re-resolving path used by
            // consumed context-menu input: blur can rebuild before focus, and
            // focus can rebuild before the press itself is routed.
            try self.handleFocusTransition(runtime, .{
                .window_id = pointer_event.window_id,
                .view_label = pointer_event.view_label,
                .blurred_id = pointer_event.blurred_id,
                .focused_id = pointer_event.focused_id,
            });
            const tree = self.treeForViewLabel(pointer_event.view_label) orelse return;
            const terminal_selected = try self.handleTerminalPointer(runtime, pointer_event);`;
  finalUiApp = replaceOnce(
    finalUiApp,
    pointerAnchor,
    pointerReplacement,
    "normal pointer focus re-resolution anchor changed",
  );

  const keyboardAnchor = `        fn handleKeyboard(self: *Self, runtime: *Runtime, keyboard_event: core.CanvasWidgetKeyboardEvent) anyerror!void {
            const tree = self.treeForViewLabel(keyboard_event.view_label) orelse return;
            // Tab/Shift+Tab already moved the runtime focus before routing
            // this key to its new target. Commit the old text field first.
            if (keyboard_event.blurred_id != 0) {
                if (tree.msgFor(keyboard_event.blurred_id, .blur)) |msg| {
                    try self.dispatch(runtime, keyboard_event.window_id, msg);
                }
            }
            if (keyboard_event.focused_id != 0) {
                if (tree.msgFor(keyboard_event.focused_id, .focus)) |msg| {
                    try self.dispatch(runtime, keyboard_event.window_id, msg);
                }
            }
            // Key precedence, top to bottom`;
  const keyboardReplacement = `        fn handleKeyboard(self: *Self, runtime: *Runtime, keyboard_event: core.CanvasWidgetKeyboardEvent) anyerror!void {
            // Normal keyboard focus also re-resolves after each dispatched
            // phase before the arriving key is routed through the live tree.
            try self.handleFocusTransition(runtime, .{
                .window_id = keyboard_event.window_id,
                .view_label = keyboard_event.view_label,
                .blurred_id = keyboard_event.blurred_id,
                .focused_id = keyboard_event.focused_id,
            });
            const tree = self.treeForViewLabel(keyboard_event.view_label) orelse return;
            // Key precedence, top to bottom`;
  finalUiApp = replaceOnce(
    finalUiApp,
    keyboardAnchor,
    keyboardReplacement,
    "normal keyboard focus re-resolution anchor changed",
  );
  writeFileSync(uiAppPath, finalUiApp);
}

// Extend the generic combobox fixture with two deliberately adversarial
// policies: blur can close the owned menu, and blur can rebuild the next
// field's focus handler. These exercise the real event seams used by Tax
// Classification without coupling SDK tests to app-specific markup.
let finalUiAppTests = readFileSync(uiAppTestsPath, "utf8");
if (!finalUiAppTests.includes("close_on_blur: bool = false")) {
  finalUiAppTests = replaceOnce(
    finalUiAppTests,
    `    focus_after_blur: bool = false,
};`,
    `    focus_after_blur: bool = false,
    close_on_blur: bool = false,
    rebind_focus_on_blur: bool = false,
    focus_handler_rebound: bool = false,
    stale_focus_count: u32 = 0,
    live_focus_count: u32 = 0,
};`,
    "focus-rebuild fixture model anchor changed",
  );
  finalUiAppTests = replaceOnce(
    finalUiAppTests,
    `    blurred,
    focused,
};`,
    `    blurred,
    focused,
    stale_focused,
    live_focused,
};`,
    "focus-rebuild fixture message anchor changed",
  );
  finalUiAppTests = replaceOnce(
    finalUiAppTests,
    `        .blurred => model.blur_count += 1,
        .focused => {
            model.focus_count += 1;
            model.focus_after_blur = model.blur_count > 0;
        },`,
    `        .blurred => {
            model.blur_count += 1;
            if (model.close_on_blur) model.open = false;
            if (model.rebind_focus_on_blur) model.focus_handler_rebound = true;
        },
        .focused => {
            model.focus_count += 1;
            model.focus_after_blur = model.blur_count > 0;
        },
        .stale_focused => model.stale_focus_count += 1,
        .live_focused => model.live_focus_count += 1,`,
    "focus-rebuild fixture update anchor changed",
  );
  finalUiAppTests = replaceOnce(
    finalUiAppTests,
    `            .on_input = ComboMirrorApp.Ui.inputMsg(.note_edit),
            .on_blur = .blurred,
            .on_focus = .focused,
        }, .{}),`,
    `            .on_input = ComboMirrorApp.Ui.inputMsg(.note_edit),
            .on_blur = .blurred,
            .on_focus = if (model.rebind_focus_on_blur)
                if (model.focus_handler_rebound) .live_focused else .stale_focused
            else
                .focused,
        }, .{}),`,
    "focus-rebuild fixture handler anchor changed",
  );
  writeFileSync(uiAppTestsPath, finalUiAppTests);
}

finalUiAppTests = readFileSync(uiAppTestsPath, "utf8");
if (
  !finalUiAppTests.includes(
    "pointer selection inside an owned combobox menu does not blur the trigger",
  )
) {
  const pointerSelectionRegression = `test "pointer selection inside an owned combobox menu does not blur the trigger" {
    const harness = try core.TestHarness().create(std.testing.allocator, .{
        .size = geometry.SizeF.init(400, 300),
    });
    defer harness.destroy(std.testing.allocator);
    harness.null_platform.gpu_surfaces = true;

    const app_state = try std.testing.allocator.create(ComboMirrorApp);
    defer std.testing.allocator.destroy(app_state);
    app_state.* = ComboMirrorApp.init(std.heap.page_allocator, .{}, .{
        .name = "ui-app-combobox-pointer-selection",
        .scene = combo_mirror_scene,
        .canvas_label = combo_mirror_canvas_label,
        .update = comboMirrorUpdate,
        .view = comboMirrorView,
    });
    defer app_state.deinit();
    app_state.model.query.set("glass");
    app_state.model.open = true;
    app_state.model.close_on_blur = true;
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
    const first_item_id = findWidgetIdByText(app_state.tree.?, .menu_item, "glass bead").?;
    try core.testing.dispatchAutomationWidgetAction(&harness.runtime, app, .{
        .view_label = combo_mirror_canvas_label,
        .id = combo_id,
        .action = .focus,
    });
    const item_frame = (try harness.runtime.canvasWidgetLayout(1, combo_mirror_canvas_label)).findById(first_item_id).?.frame;
    const x = item_frame.x + item_frame.width * 0.5;
    const y = item_frame.y + item_frame.height * 0.5;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = combo_mirror_canvas_label,
        .kind = .pointer_down,
        .x = x,
        .y = y,
        .timestamp_ns = 2_000_000,
    } });
    try std.testing.expect(app_state.model.open);
    try std.testing.expectEqual(@as(u32, 0), app_state.model.blur_count);
    try std.testing.expectEqual(first_item_id, harness.runtime.views[0].canvas_widget_focused_id);

    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = combo_mirror_canvas_label,
        .kind = .pointer_up,
        .x = x,
        .y = y,
        .timestamp_ns = 3_000_000,
    } });
    try std.testing.expect(!app_state.model.open);
}

`;
  const anchor =
    'test "text-entry on-focus dispatches after blur on real transitions" {';
  finalUiAppTests = replaceOnce(
    finalUiAppTests,
    anchor,
    `${pointerSelectionRegression}${anchor}`,
    "owned combobox pointer regression anchor changed",
  );
  writeFileSync(uiAppTestsPath, finalUiAppTests);
}

finalUiAppTests = readFileSync(uiAppTestsPath, "utf8");
if (
  !finalUiAppTests.includes(
    "pointer focus resolves the rebuilt destination handler after blur",
  )
) {
  const pointerFocusRegression = `test "pointer focus resolves the rebuilt destination handler after blur" {
    const harness = try core.TestHarness().create(std.testing.allocator, .{
        .size = geometry.SizeF.init(400, 300),
    });
    defer harness.destroy(std.testing.allocator);
    harness.null_platform.gpu_surfaces = true;

    const app_state = try std.testing.allocator.create(ComboMirrorApp);
    defer std.testing.allocator.destroy(app_state);
    app_state.* = ComboMirrorApp.init(std.heap.page_allocator, .{}, .{
        .name = "ui-app-pointer-focus-rebuild",
        .scene = combo_mirror_scene,
        .canvas_label = combo_mirror_canvas_label,
        .update = comboMirrorUpdate,
        .view = comboMirrorView,
    });
    defer app_state.deinit();
    app_state.model.rebind_focus_on_blur = true;
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
    const note_id = findWidgetIdByKind(app_state.tree.?.root, .text_field).?;
    try core.testing.dispatchAutomationWidgetAction(&harness.runtime, app, .{
        .view_label = combo_mirror_canvas_label,
        .id = combo_id,
        .action = .focus,
    });
    const note_frame = (try harness.runtime.canvasWidgetLayout(1, combo_mirror_canvas_label)).findById(note_id).?.frame;
    try harness.runtime.dispatchPlatformEvent(app, .{ .gpu_surface_input = .{
        .window_id = 1,
        .label = combo_mirror_canvas_label,
        .kind = .pointer_down,
        .x = note_frame.x + 4,
        .y = note_frame.y + note_frame.height * 0.5,
        .timestamp_ns = 2_000_000,
    } });

    try std.testing.expectEqual(note_id, harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expect(app_state.model.focus_handler_rebound);
    try std.testing.expectEqual(@as(u32, 0), app_state.model.stale_focus_count);
    try std.testing.expectEqual(@as(u32, 1), app_state.model.live_focus_count);
}

`;
  const anchor = 'test "right-click focus transitions dispatch blur then focus" {';
  finalUiAppTests = replaceOnce(
    finalUiAppTests,
    anchor,
    `${pointerFocusRegression}${anchor}`,
    "pointer focus rebuild regression anchor changed",
  );
  writeFileSync(uiAppTestsPath, finalUiAppTests);
}

finalUiAppTests = readFileSync(uiAppTestsPath, "utf8");
if (
  !finalUiAppTests.includes(
    "keyboard focus resolves the rebuilt destination handler after blur",
  )
) {
  const keyboardFocusRegression = `test "keyboard focus resolves the rebuilt destination handler after blur" {
    const harness = try core.TestHarness().create(std.testing.allocator, .{
        .size = geometry.SizeF.init(400, 300),
    });
    defer harness.destroy(std.testing.allocator);
    harness.null_platform.gpu_surfaces = true;

    const app_state = try std.testing.allocator.create(ComboMirrorApp);
    defer std.testing.allocator.destroy(app_state);
    app_state.* = ComboMirrorApp.init(std.heap.page_allocator, .{}, .{
        .name = "ui-app-keyboard-focus-rebuild",
        .scene = combo_mirror_scene,
        .canvas_label = combo_mirror_canvas_label,
        .update = comboMirrorUpdate,
        .view = comboMirrorView,
    });
    defer app_state.deinit();
    app_state.model.rebind_focus_on_blur = true;
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
    const note_id = findWidgetIdByKind(app_state.tree.?.root, .text_field).?;
    try core.testing.dispatchAutomationWidgetAction(&harness.runtime, app, .{
        .view_label = combo_mirror_canvas_label,
        .id = combo_id,
        .action = .focus,
    });
    try comboMirrorKey(harness, app, "tab");

    try std.testing.expectEqual(note_id, harness.runtime.views[0].canvas_widget_focused_id);
    try std.testing.expect(app_state.model.focus_handler_rebound);
    try std.testing.expectEqual(@as(u32, 0), app_state.model.stale_focus_count);
    try std.testing.expectEqual(@as(u32, 1), app_state.model.live_focus_count);
}

`;
  const anchor = 'test "right-click focus transitions dispatch blur then focus" {';
  finalUiAppTests = replaceOnce(
    finalUiAppTests,
    anchor,
    `${keyboardFocusRegression}${anchor}`,
    "keyboard focus rebuild regression anchor changed",
  );
  writeFileSync(uiAppTestsPath, finalUiAppTests);
}
