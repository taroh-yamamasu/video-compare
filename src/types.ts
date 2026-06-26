export type SlotId = "left" | "right";

export type LayoutMode = "side-by-side" | "stacked" | "overlay";

export interface VideoSlotState {
  id: SlotId;
  label: string;
  fileName: string | null;
  objectUrl: string | null;
  duration: number;
  currentTime: number;
  syncPointSec: number;
  isReady: boolean;
  isPlaying: boolean;
  error: string | null;
}

export interface CompareSettings {
  isLocked: boolean;
  layoutMode: LayoutMode;
  playbackRate: number;
  loopEnabled: boolean;
  loopStartSec: number;
  loopEndSec: number;
  stepSeconds: number;
}

export interface OverlaySettings {
  opacity: number;
  translateX: number;
  translateY: number;
  scale: number;
}

export interface PersistedSettings {
  isLocked: boolean;
  layoutMode: LayoutMode;
  playbackRate: number;
  stepSeconds: number;
  overlay: OverlaySettings;
}
