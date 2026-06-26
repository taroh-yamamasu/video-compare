import { useEffect } from "react";
import type { ReactElement, RefObject } from "react";
import type { VideoSlotState } from "../types";

interface VideoPlayerProps {
  slot: VideoSlotState;
  videoRef: RefObject<HTMLVideoElement | null>;
  playbackRate: number;
  className?: string;
  onLoadedMetadata: (duration: number) => void;
  onTimeUpdate: (time: number) => void;
  onPlayingChange: (isPlaying: boolean) => void;
  onError: (message: string) => void;
}

export function VideoPlayer({
  slot,
  videoRef,
  playbackRate,
  className,
  onLoadedMetadata,
  onTimeUpdate,
  onPlayingChange,
  onError,
}: VideoPlayerProps): ReactElement {
  useEffect(() => {
    if (videoRef.current) {
      videoRef.current.playbackRate = playbackRate;
    }
  }, [playbackRate, videoRef]);

  if (!slot.objectUrl) {
    return (
      <div className="video-placeholder">
        <span>{slot.label}</span>
      </div>
    );
  }

  return (
    <video
      ref={videoRef}
      className={className}
      src={slot.objectUrl}
      preload="metadata"
      playsInline
      muted
      onLoadedMetadata={(event) => {
        const video = event.currentTarget;
        video.playbackRate = playbackRate;
        if (slot.currentTime > 0 && slot.currentTime <= video.duration) {
          video.currentTime = slot.currentTime;
        }
        onLoadedMetadata(video.duration);
      }}
      onTimeUpdate={(event) => onTimeUpdate(event.currentTarget.currentTime)}
      onPlay={() => onPlayingChange(true)}
      onPause={() => onPlayingChange(false)}
      onEnded={() => onPlayingChange(false)}
      onError={() => onError("この動画はブラウザで再生できません。別の形式を選んでください。")}
    />
  );
}
