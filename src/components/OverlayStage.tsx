import type { ReactElement, RefObject } from "react";
import { VideoPlayer } from "./VideoPlayer";
import type { OverlaySettings, VideoSlotState } from "../types";

interface OverlayStageProps {
  leftSlot: VideoSlotState;
  rightSlot: VideoSlotState;
  leftVideoRef: RefObject<HTMLVideoElement | null>;
  rightVideoRef: RefObject<HTMLVideoElement | null>;
  playbackRate: number;
  overlay: OverlaySettings;
  onOverlayChange: (overlay: OverlaySettings) => void;
  onLoadedMetadata: (slotId: "left" | "right", duration: number) => void;
  onTimeUpdate: (slotId: "left" | "right", time: number) => void;
  onPlayingChange: (slotId: "left" | "right", isPlaying: boolean) => void;
  onVideoError: (slotId: "left" | "right", message: string) => void;
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
  return (
    <section className="overlay-stage" aria-label="重ね合わせ表示">
      <div className="overlay-stage__canvas">
        <VideoPlayer
          slot={leftSlot}
          videoRef={leftVideoRef}
          playbackRate={playbackRate}
          className="video-element overlay-video overlay-video--base"
          onLoadedMetadata={(duration) => onLoadedMetadata("left", duration)}
          onTimeUpdate={(time) => onTimeUpdate("left", time)}
          onPlayingChange={(isPlaying) => onPlayingChange("left", isPlaying)}
          onError={(message) => onVideoError("left", message)}
        />
        {rightSlot.objectUrl ? (
          <div
            className="overlay-stage__floating-video"
            style={{
              opacity: overlay.opacity,
              transform: `translate(${overlay.translateX}px, ${overlay.translateY}px) scale(${overlay.scale})`,
            }}
          >
            <VideoPlayer
              slot={rightSlot}
              videoRef={rightVideoRef}
              playbackRate={playbackRate}
              className="video-element overlay-video"
              onLoadedMetadata={(duration) => onLoadedMetadata("right", duration)}
              onTimeUpdate={(time) => onTimeUpdate("right", time)}
              onPlayingChange={(isPlaying) => onPlayingChange("right", isPlaying)}
              onError={(message) => onVideoError("right", message)}
            />
          </div>
        ) : null}
      </div>
      <div className="overlay-controls">
        <label>
          <span>透明度</span>
          <input
            type="range"
            min="0"
            max="1"
            step="0.01"
            value={overlay.opacity}
            onChange={(event) => onOverlayChange({ ...overlay, opacity: Number(event.currentTarget.value) })}
          />
        </label>
        <label>
          <span>X</span>
          <input
            type="range"
            min="-240"
            max="240"
            step="1"
            value={overlay.translateX}
            onChange={(event) => onOverlayChange({ ...overlay, translateX: Number(event.currentTarget.value) })}
          />
        </label>
        <label>
          <span>Y</span>
          <input
            type="range"
            min="-240"
            max="240"
            step="1"
            value={overlay.translateY}
            onChange={(event) => onOverlayChange({ ...overlay, translateY: Number(event.currentTarget.value) })}
          />
        </label>
        <label>
          <span>拡大</span>
          <input
            type="range"
            min="0.5"
            max="2"
            step="0.01"
            value={overlay.scale}
            onChange={(event) => onOverlayChange({ ...overlay, scale: Number(event.currentTarget.value) })}
          />
        </label>
      </div>
    </section>
  );
}
