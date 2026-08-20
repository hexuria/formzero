//! Session navigation and dirty-leave guards.
//!
//! Page identity, overlay and editor origins, and Stay/Discard deferral live
//! here. Persistence, profile editing, and form-page leave hygiene stay with
//! the caller: a completed move returns the leave work those owners apply.

const std = @import("std");
const form_period = @import("forms/filing_period.zig");
const profile_model = @import("tax_profile/model.zig");

pub const Page = enum {
    global_dashboard,
    taxpayer_dashboard,
    profile_setup,
    tax_form_profile,
    import_data,
    background_tasks,
    tax_calendar,
    settings,
    screen_gallery,
    form_0605,
    form_0619_e,
    form_0619_f,
    form_1601_c,
    form_1601_eq,
    form_1701,
    form_1701q,
    form_1702_rt,
    form_1702_mx,
    form_2550q,
    form_2551q,
    aux_lock_screen,
    aux_profile_auth,
    aux_admin_auth,
    aux_command_palette,
    aux_html_preview,
    aux_email_confirmation,
    aux_debug_log,
};

pub const DashboardSection = enum {
    calendar,
    forms,
    profile_settings,
};

pub const ProfileSetupSection = enum {
    tax_profile,
    reg_filing,
    tax_forms,
    email,
};

pub const PendingProfileNavigation = union(enum) {
    page: Page,
    profile_view,
    profile_section: ProfileSetupSection,
    dashboard_section: DashboardSection,
    taxpayer_slot: usize,
    new_taxpayer,
    add_branch,
    registration_taxpayer: usize,
    registration_unit: usize,
    registration_create_taxpayer,
    registration_create_branch,
};

pub const PendingTaxFormProfileNavigation = union(enum) {
    page: Page,
    return_context,
    taxpayer_slot: usize,
    new_taxpayer,
    add_branch,
    activation_segment: struct {
        form_index: usize,
        tax_year: u16,
        viewed_on: profile_model.Date,
        filing: ?form_period.FilingPeriod,
    },
};

pub const TaxpayerContextMutation = union(enum) {
    taxpayer_slot: usize,
    new_taxpayer,
    add_branch,
};

/// Unsaved work that can block a leave or a taxpayer-context change.
/// `profile` is the editor dirty flag only; viewing vs editing is `Context`.
pub const Dirty = struct {
    profile: bool = false,
    tax_form_profile: bool = false,
    taxpayer_year: bool = false,
    forms: bool = false,

    pub fn taxFormProfileSurface(self: Dirty) bool {
        return self.tax_form_profile or self.taxpayer_year;
    }
};

pub const Context = struct {
    dashboard_section: DashboardSection = .calendar,
    profile_viewing: bool = true,
    profile_creating: bool = false,
};

pub const Attempt = enum {
    completed,
    deferred_tax_form_profile,
    deferred_profile,
    rejected_forms_dirty,
};

/// Page-leave hygiene the caller owns. Empty when the move is deferred.
/// `leave_inline_profile_settings` is computed from the page being left and
/// must be applied before the caller writes the new page.
pub const LeaveWork = struct {
    leave_inline_profile_settings: bool = false,
    set_dashboard_section_calendar: bool = false,
    reset_form_filters: bool = false,
    clear_2550q_preview: bool = false,
    close_chrome: bool = false,
    reset_library_filters: bool = false,
};

pub const Request = struct {
    attempt: Attempt,
    leave: LeaveWork = .{},
};

pub const State = struct {
    page: Page = .global_dashboard,
    profile_editor_origin: Page = .global_dashboard,
    overlay_return_page: Page = .global_dashboard,
    pending_profile: ?PendingProfileNavigation = null,
    pending_tax_form_profile: ?PendingTaxFormProfileNavigation = null,
    tax_form_profile_discard_open: bool = false,

    pub fn isAuxiliaryPage(page: Page) bool {
        return switch (page) {
            .aux_lock_screen,
            .aux_profile_auth,
            .aux_admin_auth,
            .aux_command_palette,
            .aux_html_preview,
            .aux_email_confirmation,
            .aux_debug_log,
            => true,
            else => false,
        };
    }

    /// Auxiliary surfaces sit above the shell while the page that opened
    /// them remains visible underneath.
    pub fn contentPage(self: *const State) Page {
        return if (isAuxiliaryPage(self.page))
            self.overlay_return_page
        else
            self.page;
    }

    pub fn shellVisible(self: *const State) bool {
        return !isAuxiliaryPage(self.page);
    }

    /// Sidebar selection is context, not a permanent decoration. Global tools
    /// must not imply that their data is filtered by whichever profile was
    /// selected most recently.
    pub fn taxpayerSelectionVisible(
        self: *const State,
        profile_creating: bool,
    ) bool {
        return switch (self.contentPage()) {
            .taxpayer_dashboard,
            .tax_form_profile,
            .form_0605,
            .form_0619_e,
            .form_0619_f,
            .form_1601_c,
            .form_1601_eq,
            .form_1701,
            .form_1701q,
            .form_1702_rt,
            .form_1702_mx,
            .form_2550q,
            .form_2551q,
            => true,
            .profile_setup => !profile_creating,
            else => false,
        };
    }

    pub fn profileSurfaceRequiresDiscard(
        self: *const State,
        dirty: Dirty,
        ctx: Context,
    ) bool {
        if (ctx.profile_viewing or !dirty.profile) return false;
        return switch (self.page) {
            .profile_setup => true,
            .taxpayer_dashboard => ctx.dashboard_section == .profile_settings,
            else => false,
        };
    }

    pub fn parkProfile(self: *State, target: PendingProfileNavigation) void {
        self.pending_profile = target;
    }

    pub fn keepProfileEditing(self: *State) void {
        self.pending_profile = null;
    }

    pub fn takePendingProfile(self: *State) ?PendingProfileNavigation {
        const pending = self.pending_profile;
        self.pending_profile = null;
        return pending;
    }

    pub fn deferProfile(
        self: *State,
        target: PendingProfileNavigation,
        dirty: Dirty,
        ctx: Context,
    ) bool {
        if (!self.profileSurfaceRequiresDiscard(dirty, ctx)) return false;
        self.parkProfile(target);
        return true;
    }

    pub fn deferTaxFormProfile(
        self: *State,
        target: PendingTaxFormProfileNavigation,
    ) void {
        self.pending_tax_form_profile = target;
        self.tax_form_profile_discard_open = true;
    }

    pub fn keepTaxFormProfileEditing(self: *State) void {
        self.pending_tax_form_profile = null;
        self.tax_form_profile_discard_open = false;
    }

    pub fn takePendingTaxFormProfile(self: *State) PendingTaxFormProfileNavigation {
        const pending = self.pending_tax_form_profile orelse
            PendingTaxFormProfileNavigation{ .return_context = {} };
        self.pending_tax_form_profile = null;
        self.tax_form_profile_discard_open = false;
        return pending;
    }

    pub fn requestPage(
        self: *State,
        dest: Page,
        dirty: Dirty,
        ctx: Context,
    ) Request {
        if (self.page == .tax_form_profile and
            dest != .tax_form_profile and
            !isAuxiliaryPage(dest) and
            dirty.taxFormProfileSurface())
        {
            self.deferTaxFormProfile(.{ .page = dest });
            return .{ .attempt = .deferred_tax_form_profile };
        }
        if (dest != self.page and
            !isAuxiliaryPage(dest) and
            self.deferProfile(.{ .page = dest }, dirty, ctx))
        {
            return .{ .attempt = .deferred_profile };
        }

        var leave = LeaveWork{
            .close_chrome = true,
            .clear_2550q_preview = dest != .form_2550q,
            .reset_library_filters = dest != .taxpayer_dashboard,
        };
        if (self.page == .taxpayer_dashboard and
            ctx.dashboard_section == .profile_settings and
            dest != .taxpayer_dashboard and
            !isAuxiliaryPage(dest))
        {
            leave.leave_inline_profile_settings = true;
            leave.set_dashboard_section_calendar = true;
        }
        if (self.page == .taxpayer_dashboard and dest != .taxpayer_dashboard) {
            leave.reset_form_filters = true;
        }

        self.page = dest;
        return .{ .attempt = .completed, .leave = leave };
    }

    pub fn openTransient(
        self: *State,
        dest: Page,
        dirty: Dirty,
        ctx: Context,
    ) Request {
        if (self.page != dest) self.overlay_return_page = self.contentPage();
        return self.requestPage(dest, dirty, ctx);
    }

    pub fn closeTransient(self: *State, dirty: Dirty, ctx: Context) Request {
        const destination = self.overlay_return_page;
        self.overlay_return_page = .global_dashboard;
        return self.requestPage(destination, dirty, ctx);
    }

    pub fn openProfileEditor(
        self: *State,
        dirty: Dirty,
        ctx: Context,
    ) Request {
        if (self.page != .profile_setup) {
            self.profile_editor_origin = self.contentPage();
        }
        return self.requestPage(.profile_setup, dirty, ctx);
    }

    /// Dirty Back parks a leave to the remembered origin and does not cancel
    /// the editor. A clean close still needs the caller to restore view mode
    /// before the completed leave work is applied.
    pub fn closeProfileEditor(
        self: *State,
        dirty: Dirty,
        ctx: Context,
    ) Request {
        const destination = self.profile_editor_origin;
        if (self.deferProfile(.{ .page = destination }, dirty, ctx)) {
            return .{ .attempt = .deferred_profile };
        }
        const result = self.requestPage(destination, dirty, ctx);
        if (self.page != .profile_setup) {
            self.profile_editor_origin = .global_dashboard;
        }
        return result;
    }

    /// Taxpayer-context actions must be rejected or deferred before they
    /// mutate the selected profile, Forms Set workspace, or annual Tax Form
    /// Profile. Tax Form Profile dirty wins, then the profile editor, then
    /// the Forms Set workspace.
    pub fn guardTaxpayerContext(
        self: *State,
        target: TaxpayerContextMutation,
        dirty: Dirty,
        ctx: Context,
    ) Attempt {
        if (self.page == .tax_form_profile and dirty.taxFormProfileSurface()) {
            self.deferTaxFormProfile(taxFormProfilePendingFrom(target));
            return .deferred_tax_form_profile;
        }
        if (self.deferProfile(profilePendingFrom(target), dirty, ctx)) {
            return .deferred_profile;
        }
        if (dirty.forms) return .rejected_forms_dirty;
        return .completed;
    }
};

fn profilePendingFrom(target: TaxpayerContextMutation) PendingProfileNavigation {
    return switch (target) {
        .taxpayer_slot => |slot| .{ .taxpayer_slot = slot },
        .new_taxpayer => .new_taxpayer,
        .add_branch => .add_branch,
    };
}

fn taxFormProfilePendingFrom(
    target: TaxpayerContextMutation,
) PendingTaxFormProfileNavigation {
    return switch (target) {
        .taxpayer_slot => |slot| .{ .taxpayer_slot = slot },
        .new_taxpayer => .new_taxpayer,
        .add_branch => .add_branch,
    };
}

const clean = Dirty{};
const default_ctx = Context{};

fn expectCompleted(result: Request) !void {
    try std.testing.expectEqual(Attempt.completed, result.attempt);
}

fn expectDeferredProfile(result: Request) !void {
    try std.testing.expectEqual(Attempt.deferred_profile, result.attempt);
    try std.testing.expectEqual(false, result.leave.close_chrome);
}

fn expectDeferredTaxFormProfile(result: Request) !void {
    try std.testing.expectEqual(Attempt.deferred_tax_form_profile, result.attempt);
    try std.testing.expectEqual(false, result.leave.close_chrome);
}

test "auxiliary pages keep the originating content page visible" {
    var state = State{ .page = .form_1701q };
    _ = state.openTransient(.aux_html_preview, clean, default_ctx);
    try std.testing.expectEqual(Page.aux_html_preview, state.page);
    try std.testing.expectEqual(Page.form_1701q, state.overlay_return_page);
    try std.testing.expectEqual(Page.form_1701q, state.contentPage());
    try std.testing.expect(!state.shellVisible());

    const closed = state.closeTransient(clean, default_ctx);
    try expectCompleted(closed);
    try std.testing.expectEqual(Page.form_1701q, state.page);
    try std.testing.expectEqual(Page.global_dashboard, state.overlay_return_page);
    try std.testing.expect(state.shellVisible());
}

test "taxpayer selection is hidden on global routes and new-profile setup" {
    var state = State{};
    const hidden = [_]Page{
        .global_dashboard,
        .tax_calendar,
        .settings,
        .import_data,
        .background_tasks,
        .screen_gallery,
    };
    for (hidden) |page| {
        state.page = page;
        try std.testing.expect(!state.taxpayerSelectionVisible(false));
    }

    state.page = .taxpayer_dashboard;
    try std.testing.expect(state.taxpayerSelectionVisible(false));
    state.page = .form_1701q;
    try std.testing.expect(state.taxpayerSelectionVisible(false));
    state.page = .profile_setup;
    try std.testing.expect(!state.taxpayerSelectionVisible(true));
    try std.testing.expect(state.taxpayerSelectionVisible(false));
}

test "clean requestPage changes the page and asks for chrome close" {
    var state = State{ .page = .global_dashboard };
    const result = state.requestPage(.settings, clean, default_ctx);
    try expectCompleted(result);
    try std.testing.expectEqual(Page.settings, state.page);
    try std.testing.expect(result.leave.close_chrome);
    try std.testing.expect(result.leave.clear_2550q_preview);
    try std.testing.expect(result.leave.reset_library_filters);
    try std.testing.expect(!result.leave.reset_form_filters);
}

test "leaving the taxpayer dashboard resets form filters even for overlays" {
    var state = State{ .page = .taxpayer_dashboard };
    const result = state.requestPage(.aux_command_palette, clean, default_ctx);
    try expectCompleted(result);
    try std.testing.expect(result.leave.reset_form_filters);
    try std.testing.expect(!result.leave.leave_inline_profile_settings);
}

test "leaving inline profile settings asks the caller to restore view mode" {
    var state = State{ .page = .taxpayer_dashboard };
    const ctx = Context{ .dashboard_section = .profile_settings };
    const result = state.requestPage(.global_dashboard, clean, ctx);
    try expectCompleted(result);
    try std.testing.expect(result.leave.leave_inline_profile_settings);
    try std.testing.expect(result.leave.set_dashboard_section_calendar);
    try std.testing.expect(result.leave.reset_form_filters);
}

test "opening 2550Q keeps a resolved preview that every other page clears" {
    var state = State{ .page = .profile_setup };
    const keep = state.requestPage(.form_2550q, clean, default_ctx);
    try expectCompleted(keep);
    try std.testing.expect(!keep.leave.clear_2550q_preview);

    const clear = state.requestPage(.screen_gallery, clean, default_ctx);
    try expectCompleted(clear);
    try std.testing.expect(clear.leave.clear_2550q_preview);
}

test "dirty tax form profile parks a leave and keeps the page" {
    var state = State{ .page = .tax_form_profile };
    const dirty = Dirty{ .tax_form_profile = true };
    const result = state.requestPage(.global_dashboard, dirty, default_ctx);
    try expectDeferredTaxFormProfile(result);
    try std.testing.expectEqual(Page.tax_form_profile, state.page);
    try std.testing.expect(state.tax_form_profile_discard_open);
    try std.testing.expectEqual(
        Page.global_dashboard,
        state.pending_tax_form_profile.?.page,
    );
}

test "dirty taxpayer-year settings use the same tax form profile guard" {
    var state = State{ .page = .tax_form_profile };
    const dirty = Dirty{ .taxpayer_year = true };
    const result = state.requestPage(.settings, dirty, default_ctx);
    try expectDeferredTaxFormProfile(result);
    try std.testing.expectEqual(Page.tax_form_profile, state.page);
}

test "auxiliary pages do not trigger the tax form profile discard prompt" {
    var state = State{ .page = .tax_form_profile };
    const dirty = Dirty{ .tax_form_profile = true };
    const result = state.openTransient(.aux_command_palette, dirty, default_ctx);
    try expectCompleted(result);
    try std.testing.expectEqual(Page.aux_command_palette, state.page);
    try std.testing.expectEqual(Page.tax_form_profile, state.contentPage());
    try std.testing.expect(state.pending_tax_form_profile == null);
}

test "dirty profile setup parks a leave and keeps the editor" {
    var state = State{ .page = .profile_setup };
    const dirty = Dirty{ .profile = true };
    const ctx = Context{ .profile_viewing = false };
    const result = state.requestPage(.global_dashboard, dirty, ctx);
    try expectDeferredProfile(result);
    try std.testing.expectEqual(Page.profile_setup, state.page);
    try std.testing.expectEqual(
        Page.global_dashboard,
        state.pending_profile.?.page,
    );
}

test "dirty inline profile settings block dashboard tab and page changes" {
    var state = State{ .page = .taxpayer_dashboard };
    const dirty = Dirty{ .profile = true };
    const ctx = Context{
        .dashboard_section = .profile_settings,
        .profile_viewing = false,
    };
    try std.testing.expect(state.deferProfile(.{ .dashboard_section = .forms }, dirty, ctx));
    try std.testing.expectEqual(
        DashboardSection.forms,
        state.pending_profile.?.dashboard_section,
    );
    try std.testing.expectEqual(Page.taxpayer_dashboard, state.page);

    state.keepProfileEditing();
    const page_leave = state.requestPage(.global_dashboard, dirty, ctx);
    try expectDeferredProfile(page_leave);
    try std.testing.expectEqual(Page.taxpayer_dashboard, state.page);
}

test "viewing or clean profile surfaces never park a discard prompt" {
    var viewing = State{ .page = .profile_setup };
    try std.testing.expect(!viewing.profileSurfaceRequiresDiscard(
        .{ .profile = true },
        .{ .profile_viewing = true },
    ));
    var clean_editor = State{ .page = .profile_setup };
    try std.testing.expect(!clean_editor.profileSurfaceRequiresDiscard(
        .{},
        .{ .profile_viewing = false },
    ));
    var other_page = State{ .page = .settings };
    try std.testing.expect(!other_page.profileSurfaceRequiresDiscard(
        .{ .profile = true },
        .{ .profile_viewing = false },
    ));
}

test "same-page request does not park a dirty profile leave" {
    var state = State{ .page = .profile_setup };
    const dirty = Dirty{ .profile = true };
    const ctx = Context{ .profile_viewing = false };
    const result = state.requestPage(.profile_setup, dirty, ctx);
    try expectCompleted(result);
    try std.testing.expect(state.pending_profile == null);
    try std.testing.expect(result.leave.close_chrome);
}

test "openProfileEditor remembers the content page that opened it" {
    var state = State{ .page = .taxpayer_dashboard };
    const result = state.openProfileEditor(clean, default_ctx);
    try expectCompleted(result);
    try std.testing.expectEqual(Page.profile_setup, state.page);
    try std.testing.expectEqual(Page.taxpayer_dashboard, state.profile_editor_origin);
}

test "closeProfileEditor returns clean edits and guards dirty edits" {
    var state = State{
        .page = .profile_setup,
        .profile_editor_origin = .taxpayer_dashboard,
    };
    const clean_close = state.closeProfileEditor(
        .{},
        .{ .profile_viewing = false },
    );
    try expectCompleted(clean_close);
    try std.testing.expectEqual(Page.taxpayer_dashboard, state.page);
    try std.testing.expectEqual(Page.global_dashboard, state.profile_editor_origin);

    state = .{
        .page = .profile_setup,
        .profile_editor_origin = .taxpayer_dashboard,
    };
    const dirty_close = state.closeProfileEditor(
        .{ .profile = true },
        .{ .profile_viewing = false },
    );
    try expectDeferredProfile(dirty_close);
    try std.testing.expectEqual(Page.profile_setup, state.page);
    try std.testing.expectEqual(Page.taxpayer_dashboard, state.profile_editor_origin);
    try std.testing.expectEqual(
        Page.taxpayer_dashboard,
        state.pending_profile.?.page,
    );
}

test "taxpayer-context guards prefer tax form profile then profile then forms" {
    var state = State{ .page = .tax_form_profile };
    const all_dirty = Dirty{
        .profile = true,
        .tax_form_profile = true,
        .forms = true,
    };
    const editing = Context{ .profile_viewing = false };
    try std.testing.expectEqual(
        Attempt.deferred_tax_form_profile,
        state.guardTaxpayerContext(.new_taxpayer, all_dirty, editing),
    );
    try std.testing.expect(state.tax_form_profile_discard_open);

    state = .{ .page = .profile_setup };
    try std.testing.expectEqual(
        Attempt.deferred_profile,
        state.guardTaxpayerContext(.{ .taxpayer_slot = 2 }, all_dirty, editing),
    );
    try std.testing.expectEqual(@as(usize, 2), state.pending_profile.?.taxpayer_slot);

    state = .{ .page = .taxpayer_dashboard };
    try std.testing.expectEqual(
        Attempt.rejected_forms_dirty,
        state.guardTaxpayerContext(.add_branch, .{ .forms = true }, default_ctx),
    );
    try std.testing.expect(state.pending_profile == null);

    try std.testing.expectEqual(
        Attempt.completed,
        state.guardTaxpayerContext(.add_branch, clean, default_ctx),
    );
}

test "keep and take clear parked discard prompts" {
    var state = State{ .page = .profile_setup };
    state.parkProfile(.profile_view);
    try std.testing.expect(state.pending_profile != null);
    state.keepProfileEditing();
    try std.testing.expect(state.pending_profile == null);

    state.parkProfile(.{ .page = .settings });
    try std.testing.expectEqual(
        Page.settings,
        state.takePendingProfile().?.page,
    );
    try std.testing.expect(state.pending_profile == null);

    state.deferTaxFormProfile(.{ .return_context = {} });
    try std.testing.expect(state.tax_form_profile_discard_open);
    try std.testing.expectEqual(
        .return_context,
        std.meta.activeTag(state.takePendingTaxFormProfile()),
    );
    try std.testing.expect(!state.tax_form_profile_discard_open);
}
