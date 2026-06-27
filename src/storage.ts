import type { CompareSettings, OverlaySettings, OverlayTransform, PersistedSettings, SlotId } from "./types";

const STORAGE_KEY = "video-compare-ui-settings";
const SETTINGS_VERSION = 3;

type LegacyOverlaySettings = Partial<OverlaySettings> & Partial<OverlayTransform>;

function isSlotId(value: unknown): value is SlotId {
  return value === "left" || value === "right";
}

function readFiniteNumber(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function normalizeOverlayTransform(
  source: Partial<OverlayTransform> | undefined,
  defaults: OverlayTransform,
): OverlayTransform {
  const opacity = readFiniteNumber(source?.opacity, defaults.opacity);
  const scale = readFiniteNumber(source?.scale, defaults.scale);

  return {
    opacity: Math.min(1, Math.max(0, opacity)),
    translateX: readFiniteNumber(source?.translateX, defaults.translateX),
    translateY: readFiniteNumber(source?.translateY, defaults.translateY),
    scale: Math.min(4, Math.max(0.1, scale)),
  };
}

function normalizeOverlaySettings(
  source: LegacyOverlaySettings | undefined,
  defaults: OverlaySettings,
): OverlaySettings {
  const transforms = source?.transforms as Partial<Record<SlotId, Partial<OverlayTransform>>> | undefined;

  return {
    editingSlot: isSlotId(source?.editingSlot) ? source.editingSlot : defaults.editingSlot,
    transforms: {
      left: normalizeOverlayTransform(transforms?.left, defaults.transforms.left),
      right: normalizeOverlayTransform(transforms?.right ?? source, defaults.transforms.right),
    },
  };
}

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
    const preservesPlaybackRate = typeof parsed.version === "number" && parsed.version >= 2;

    return {
      version: SETTINGS_VERSION,
      isLocked: typeof parsed.isLocked === "boolean" ? parsed.isLocked : compareDefaults.isLocked,
      layoutMode:
        parsed.layoutMode === "side-by-side" || parsed.layoutMode === "stacked" || parsed.layoutMode === "overlay"
          ? parsed.layoutMode
          : compareDefaults.layoutMode,
      playbackRate:
        preservesPlaybackRate && typeof parsed.playbackRate === "number" && parsed.playbackRate > 0
          ? parsed.playbackRate
          : compareDefaults.playbackRate,
      stepSeconds:
        typeof parsed.stepSeconds === "number" && parsed.stepSeconds > 0
          ? parsed.stepSeconds
          : compareDefaults.stepSeconds,
      overlay: normalizeOverlaySettings(parsed.overlay as LegacyOverlaySettings | undefined, overlayDefaults),
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
