import type { CompareSettings, OverlaySettings, SlotId, VideoSlotState } from "./types";

export const DEFAULT_COMPARE_SETTINGS: CompareSettings = {
  isLocked: true,
  layoutMode: "side-by-side",
  playbackRate: 1,
  loopEnabled: false,
  loopStartSec: 0,
  loopEndSec: 3,
  stepSeconds: 1 / 30,
};

export const DEFAULT_OVERLAY_SETTINGS: OverlaySettings = {
  opacity: 0.5,
  translateX: 0,
  translateY: 0,
  scale: 1,
};

export function createInitialSlot(id: SlotId): VideoSlotState {
  return {
    id,
    label: id === "left" ? "左動画" : "右動画",
    fileName: null,
    objectUrl: null,
    duration: 0,
    videoWidth: 0,
    videoHeight: 0,
    currentTime: 0,
    syncPointSec: 0,
    viewScale: 1,
    viewOffsetX: 0,
    viewOffsetY: 0,
    hasSyncPoint: false,
    isReady: false,
    isPlaying: false,
    error: null,
  };
}
