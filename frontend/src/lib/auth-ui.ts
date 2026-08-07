// Shared visual language for the whole app -- started as the auth pages'
// design system (login, register, forgot/reset password: same card, same
// inputs, same buttons) and extended here to the dashboard/games/game-detail
// pages so there's one design-token source of truth rather than a second,
// competing style module. Zinc neutrals + one indigo accent throughout,
// dark-mode-aware via Tailwind's `dark:` variant everywhere.

export const authPageWrap =
  "min-h-full flex items-center justify-center px-4 py-16 bg-gradient-to-b from-zinc-50 to-zinc-100 dark:from-zinc-950 dark:to-black";

export const authCard =
  "w-full max-w-sm rounded-2xl border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 p-8 shadow-sm";

export const authBrand = "text-sm font-medium tracking-wide text-indigo-600 dark:text-indigo-400 mb-1";

export const authTitle = "text-2xl font-semibold text-zinc-900 dark:text-zinc-50";

export const authSubtitle = "mt-1 text-sm text-zinc-500 dark:text-zinc-400 mb-6";

export const authInput =
  "w-full rounded-lg border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-800 " +
  "px-3 py-2 text-sm text-zinc-900 dark:text-zinc-100 placeholder:text-zinc-400 " +
  "focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent";

export const authButtonPrimary =
  "w-full rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-500 " +
  "disabled:opacity-50 disabled:cursor-not-allowed transition-colors";

export const authLink = "text-indigo-600 dark:text-indigo-400 hover:underline";

export const authError =
  "rounded-lg bg-red-50 dark:bg-red-950/40 border border-red-200 dark:border-red-900 " +
  "px-3 py-2 text-sm text-red-700 dark:text-red-400";

// ---- App-wide (dashboard / games list / game detail) ----

export const pageWrap =
  "min-h-full bg-gradient-to-b from-zinc-50 to-zinc-100 dark:from-zinc-950 dark:to-black px-4 py-8";

export const pageInner = "max-w-5xl mx-auto";

export const navBar = "flex items-center justify-between max-w-5xl mx-auto mb-8";

export const navBrand = "text-lg font-semibold tracking-tight text-zinc-900 dark:text-zinc-50";

export const navBrandAccent = "text-indigo-600 dark:text-indigo-400";

export const card =
  "rounded-2xl border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 p-6 shadow-sm";

export const sectionTitle = "text-lg font-semibold text-zinc-900 dark:text-zinc-50";

export const mutedText = "text-sm text-zinc-500 dark:text-zinc-400";

export const pageTitle = "text-2xl font-semibold text-zinc-900 dark:text-zinc-50 mb-6";

// Non-full-width sibling of authButtonPrimary -- that's `w-full` (right for
// a stacked auth form), these are for inline button groups (game actions,
// new-game controls).
export const buttonPrimary =
  "rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-500 " +
  "disabled:opacity-50 disabled:cursor-not-allowed transition-colors";

export const buttonSecondary =
  "rounded-lg border border-zinc-300 dark:border-zinc-700 px-4 py-2 text-sm font-medium " +
  "text-zinc-700 dark:text-zinc-200 hover:bg-zinc-50 dark:hover:bg-zinc-800 transition-colors " +
  "disabled:opacity-50 disabled:cursor-not-allowed";

export const buttonDanger =
  "rounded-lg border border-red-200 dark:border-red-900 px-4 py-2 text-sm font-medium " +
  "text-red-600 dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-950/40 transition-colors " +
  "disabled:opacity-50 disabled:cursor-not-allowed";

export const linkButton =
  "text-sm text-indigo-600 dark:text-indigo-400 hover:underline disabled:opacity-50 disabled:no-underline " +
  "disabled:cursor-not-allowed";

// A pill-toggle group (game type, color picker) -- `segmentedOption(active)`
// picks the "pressed" vs. idle look for each button inside a `segmentedGroup`.
export const segmentedGroup =
  "inline-flex items-center gap-1 rounded-lg border border-zinc-300 dark:border-zinc-700 " +
  "bg-zinc-100 dark:bg-zinc-800 p-1";

export function segmentedOption(active: boolean): string {
  return active
    ? "rounded-md bg-white dark:bg-zinc-900 px-3 py-1.5 text-sm font-medium text-zinc-900 dark:text-zinc-50 shadow-sm"
    : "rounded-md px-3 py-1.5 text-sm font-medium text-zinc-500 dark:text-zinc-400 " +
        "hover:text-zinc-700 dark:hover:text-zinc-200 transition-colors";
}

const CLASSIFICATION_STYLES: Record<string, string> = {
  best: "bg-emerald-100 text-emerald-700 dark:bg-emerald-950/50 dark:text-emerald-400",
  good: "bg-teal-100 text-teal-700 dark:bg-teal-950/50 dark:text-teal-400",
  inaccuracy: "bg-amber-100 text-amber-700 dark:bg-amber-950/50 dark:text-amber-400",
  mistake: "bg-orange-100 text-orange-700 dark:bg-orange-950/50 dark:text-orange-400",
  blunder: "bg-red-100 text-red-700 dark:bg-red-950/50 dark:text-red-400",
};

export function classificationBadgeClass(classification: string | null): string {
  const palette = CLASSIFICATION_STYLES[classification ?? ""] ?? "bg-zinc-100 text-zinc-500 dark:bg-zinc-800 dark:text-zinc-400";
  return `inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium capitalize ${palette}`;
}
