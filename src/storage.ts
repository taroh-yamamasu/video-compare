import type { CompareSettings, OverlaySettings, PersistedSettings } from "./types";

const STORAGE_KEY = "video-compare-ui-settings";
const SETTINGS_VERSION = 2;

export function loadPersistedSettings(
  compareDefaults: CompareSettings,
  overlayDefaults: OverlaySettings,
): PersistedSettings {
  if (typeof window === "undefined") {
    return toPersistedSettings(compareDefaults, overlayDefaults);
  }

  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) {
      return toPersistedSettings(compareDefaults, overlayDefaults);
    }

    const parsed = JSON.parse(raw) as Partial<PersistedSettings>;
    const isCurrentVersion = parsed.version === SETTINGS_VERSION;

    return {
      version: SETTINGS_VERSION,
      isLocked: typeof parsed.isLocked === "boolean" ? parsed.isLocked : compareDefaults.isLocked,
      layoutMode:
        parsed.layoutMode === "side-by-side" || parsed.layoutMode === "stacked" || parsed.layoutMode === "overlay"
          ? parsed.layoutMode
          : compareDefaults.layoutMode,
      playbackRate:
        isCurrentVersion && typeof parsed.playbackRate === "number" && parsed.playbackRate > 0
          ? parsed.playbackRate
          : compareDefaults.playbackRate,
      stepSeconds:
        typeof parsed.stepSeconds === "number" && parsed.stepSeconds > 0
          ? parsed.stepSeconds
          : compareDefaults.stepSeconds,
      overlay: {
        opacity:
          typeof parsed.overlay?.opacity === "number" ? parsed.overlay.opacity : overlayDefaults.opacity,
        translateX:
          typeof parsed.overlay?.translateX === "number" ? parsed.overlay.translateX : overlayDefaults.translateX,
        translateY:
          typeof parsed.overlay?.translateY === "number" ? parsed.overlay.translateY : overlayDefaults.translateY,
        scale: typeof parsed.overlay?.scale === "number" ? parsed.overlay.scale : overlayDefaults.scale,
      },
    };
  } catch {
    return toPersistedSettings(compareDefaults, overlayDefaults);
  }
}

export function savePersistedSettings(settings: PersistedSettings): void {
  if (typeof window === "undefined") {
    return;
  }

  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
}

export function toPersistedSettings(
  compare: CompareSettings,
  overlay: OverlaySettings,
): PersistedSettings {
  return {
    version: SETTINGS_VERSION,
    isLocked: compare.isLocked,
    layoutMode: compare.layoutMode,
    playbackRate: compare.playbackRate,
    stepSeconds: compare.stepSeconds,
    overlay,
  };
}
