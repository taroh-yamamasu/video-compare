export type SlotId = "left" | "right";

export type LayoutMode = "side-by-side" | "stacked" | "overlay";

export interface VideoSlotState {
  id: SlotId;
  label: string;
  fileName: string | null;
  objectUrl: string | null;
  duration: number;
  videoWidth: number;
  videoHeight: number;
  currentTime: number;
  syncPointSec: number;
  viewScale: number;
  viewOffsetX: number;
  viewOffsetY: number;
  hasSyncPoint: boolean;
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

export interface OverlayTransform {
  opacity: number;
  translateX: number;
  translateY: number;
  scale: number;
}

export interface OverlaySettings {
  editingSlot: SlotId;
  transforms: Record<SlotId, OverlayTransform>;
}

export interface PersistedSettings {
  version: number;
  isLocked: boolean;
  layoutMode: LayoutMode;
  playbackRate: number;
  stepSeconds: number;
  overlay: OverlaySettings;
}
