import type { CSSProperties, ReactElement, RefObject } from "react";
import { VideoPlayer } from "./VideoPlayer";
import type { OverlaySettings, OverlayTransform, SlotId, VideoSlotState } from "../types";

interface OverlayStageProps {
  leftSlot: VideoSlotState;
  rightSlot: VideoSlotState;
  leftVideoRef: RefObject<HTMLVideoElement | null>;
  rightVideoRef: RefObject<HTMLVideoElement | null>;
  playbackRate: number;
  overlay: OverlaySettings;
  onOverlayChange: (overlay: OverlaySettings) => void;
  onLoadedMetadata: (
    slotId: "left" | "right",
    metadata: { duration: number; videoWidth: number; videoHeight: number },
  ) => void;
  onTimeUpdate: (slotId: "left" | "right", time: number) => void;
  onPlayingChange: (slotId: "left" | "right", isPlaying: boolean) => void;
  onVideoError: (slotId: "left" | "right", message: string) => void;
}

function getSlotViewTransform(slot: VideoSlotState): string {
  return `translate(${slot.viewOffsetX}px, ${slot.viewOffsetY}px) scale(${slot.viewScale})`;
}

function getOverlayLayerStyle(
  slotId: SlotId,
  editingSlot: SlotId,
  transform: OverlayTransform,
): CSSProperties {
  return {
    opacity: slotId === editingSlot ? transform.opacity : 1,
    transform: `translate(${transform.translateX}px, ${transform.translateY}px) scale(${transform.scale})`,
    zIndex: slotId === editingSlot ? 2 : 1,
  };
}

export function OverlayStage({
  leftSlot,
  rightSlot,
  leftVideoRef,
  rightVideoRef,
  playbackRate,
  overlay,
  onOverlayChange,
  onLoadedMetadata,
  onTimeUpdate,
  onPlayingChange,
  onVideoError,
}: OverlayStageProps): ReactElement {
  const activeTransform = overlay.transforms[overlay.editingSlot];
  const slots: Record<SlotId, VideoSlotState> = {
    left: leftSlot,
    right: rightSlot,
  };
  const videoRefs: Record<SlotId, RefObject<HTMLVideoElement | null>> = {
    left: leftVideoRef,
    right: rightVideoRef,
  };
  const hasAnyVideo = Boolean(leftSlot.objectUrl || rightSlot.objectUrl);

  function updateEditingSlot(editingSlot: SlotId): void {
    onOverlayChange({
      ...overlay,
      editingSlot,
    });
  }

  function updateActiveTransform(patch: Partial<OverlayTransform>): void {
    onOverlayChange({
      ...overlay,
      transforms: {
        ...overlay.transforms,
        [overlay.editingSlot]: {
          ...activeTransform,
          ...patch,
        },
      },
    });
  }

  function renderLayer(slotId: SlotId): ReactElement {
    const slot = slots[slotId];
    const isEditing = slotId === overlay.editingSlot;

    if (!slot.objectUrl && (hasAnyVideo || slotId === "right")) {
      return <div key={slotId} />;
    }

    return (
      <div
        key={slotId}
        className={`overlay-stage__layer ${isEditing ? "overlay-stage__layer--editing" : ""}`}
        style={getOverlayLayerStyle(slotId, overlay.editingSlot, overlay.transforms[slotId])}
      >
        <div className="overlay-stage__slot-transform" style={{ transform: getSlotViewTransform(slot) }}>
          <VideoPlayer
            slot={slot}
            videoRef={videoRefs[slotId]}
            playbackRate={playbackRate}
            className="video-element overlay-video"
            onLoadedMetadata={(metadata) => onLoadedMetadata(slotId, metadata)}
            onTimeUpdate={(time) => onTimeUpdate(slotId, time)}
            onPlayingChange={(isPlaying) => onPlayingChange(slotId, isPlaying)}
            onError={(message) => onVideoError(slotId, message)}
          />
        </div>
      </div>
    );
  }

  return (
    <section className="overlay-stage" aria-label="重ね合わせ表示">
      <div className="overlay-stage__canvas">
        {renderLayer("left")}
        {renderLayer("right")}
      </div>
      <div className="overlay-controls">
        <div className="overlay-target-control">
          <span>調整</span>
          <div className="segmented-control" aria-label="重ね調整の対象">
            <button
              type="button"
              className={overlay.editingSlot === "left" ? "is-active" : ""}
              onClick={() => updateEditingSlot("left")}
              aria-pressed={overlay.editingSlot === "left"}
            >
              左動画
            </button>
            <button
              type="button"
              className={overlay.editingSlot === "right" ? "is-active" : ""}
              onClick={() => updateEditingSlot("right")}
              aria-pressed={overlay.editingSlot === "right"}
            >
              右動画
            </button>
          </div>
        </div>
        <label>
          <span>透明度</span>
          <input
            type="range"
            min="0"
            max="1"
            step="0.01"
            value={activeTransform.opacity}
            onChange={(event) => updateActiveTransform({ opacity: Number(event.currentTarget.value) })}
          />
        </label>
        <label>
          <span>X</span>
          <input
            type="range"
            min="-240"
            max="240"
            step="1"
            value={activeTransform.translateX}
            onChange={(event) => updateActiveTransform({ translateX: Number(event.currentTarget.value) })}
          />
        </label>
        <label>
          <span>Y</span>
          <input
            type="range"
            min="-240"
            max="240"
            step="1"
            value={activeTransform.translateY}
            onChange={(event) => updateActiveTransform({ translateY: Number(event.currentTarget.value) })}
          />
        </label>
        <label>
          <span>拡大</span>
          <input
            type="range"
            min="0.5"
            max="2"
            step="0.01"
            value={activeTransform.scale}
            onChange={(event) => updateActiveTransform({ scale: Number(event.currentTarget.value) })}
          />
        </label>
      </div>
    </section>
  );
}
