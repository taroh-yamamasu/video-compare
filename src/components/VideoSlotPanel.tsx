import { CircleDot, Trash2, Upload, Video } from "lucide-react";
import { useRef, useState } from "react";
import type { CSSProperties, ReactElement, ReactNode } from "react";
import type { VideoSlotState } from "../types";
import { clamp, formatTime } from "../utils/time";

interface VideoSlotPanelProps {
  slot: VideoSlotState;
  compact?: boolean;
  children?: ReactNode;
  videoFrameStyle?: CSSProperties;
  isCompareActive: boolean;
  onFileSelected: (file: File) => void;
  onSeek: (time: number) => void;
  onSetSyncPoint: () => void;
  onClear: () => void;
}

export function VideoSlotPanel({
  slot,
  compact = false,
  children,
  videoFrameStyle,
  isCompareActive,
  onFileSelected,
  onSeek,
  onSetSyncPoint,
  onClear,
}: VideoSlotPanelProps): ReactElement {
  const inputRef = useRef<HTMLInputElement | null>(null);
  const [isDragging, setIsDragging] = useState(false);

  function openPicker(): void {
    inputRef.current?.click();
  }

  function handleFiles(files: FileList | null): void {
    const file = files?.item(0);
    if (file) {
      onFileSelected(file);
    }
  }

  return (
    <section
      className={`slot-panel ${compact ? "slot-panel--compact" : ""} ${slot.objectUrl ? "has-video" : ""} ${
        isDragging ? "is-dragging" : ""
      }`}
      onDragEnter={(event) => {
        event.preventDefault();
        setIsDragging(true);
      }}
      onDragOver={(event) => event.preventDefault()}
      onDragLeave={() => setIsDragging(false)}
      onDrop={(event) => {
        event.preventDefault();
        setIsDragging(false);
        handleFiles(event.dataTransfer.files);
      }}
      aria-label={slot.label}
    >
      <input
        ref={inputRef}
        className="sr-only"
        type="file"
        accept="video/*,.mov,.mp4"
        onChange={(event) => {
          handleFiles(event.currentTarget.files);
          event.currentTarget.value = "";
        }}
      />

      {!isCompareActive ? (
        <>
          <div className="slot-panel__header">
            <div className="slot-panel__title">
              <Video size={18} aria-hidden="true" />
              <div>
                <h2>{slot.label}</h2>
                <p>{slot.fileName ?? "未選択"}</p>
              </div>
            </div>
            {slot.objectUrl ? (
              <button type="button" className="icon-button" onClick={onClear} aria-label={`${slot.label}をクリア`}>
                <Trash2 size={18} aria-hidden="true" />
              </button>
            ) : null}
          </div>

          <button type="button" className="select-video-button" onClick={openPicker}>
            <Upload size={20} aria-hidden="true" />
            写真から選ぶ
          </button>
        </>
      ) : null}

      {!compact ? (
        <div className="slot-panel__video" style={videoFrameStyle}>
          {children}
        </div>
      ) : null}

      {slot.error ? <p className="slot-error">{slot.error}</p> : null}

      {!isCompareActive ? (
        <div className="slot-panel__controls">
          <div className="time-row">
            <span>{formatTime(slot.currentTime)}</span>
            <span>{formatTime(slot.duration)}</span>
          </div>
          <input
            type="range"
            min="0"
            max={slot.duration || 0}
            step="0.001"
            value={clamp(slot.currentTime, 0, slot.duration || 0)}
            disabled={!slot.isReady}
            onChange={(event) => onSeek(Number(event.currentTarget.value))}
            aria-label={`${slot.label}の再生位置`}
          />
          <div className="slot-panel__actions slot-panel__actions--sync">
            <button type="button" onClick={onSetSyncPoint} disabled={!slot.isReady}>
              <CircleDot size={17} aria-hidden="true" />
              基準点
            </button>
            <span className="sync-readout">{formatTime(slot.syncPointSec)}</span>
          </div>
        </div>
      ) : null}
    </section>
  );
}
