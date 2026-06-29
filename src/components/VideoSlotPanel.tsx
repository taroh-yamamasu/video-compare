import { CheckCircle2, CircleDot, Minus, Plus, RotateCcw, Trash2, Upload, Video } from "lucide-react";
import { useRef, useState } from "react";
import type { CSSProperties, PointerEvent, ReactElement, ReactNode } from "react";
import type { VideoSlotState } from "../types";
import { clamp, formatTime } from "../utils/time";

const MIN_VIEW_SCALE = 1;
const MAX_VIEW_SCALE = 4;
const VIEW_SCALE_STEP = 0.25;

interface VideoSlotPanelProps {
  slot: VideoSlotState;
  compact?: boolean;
  children?: ReactNode;
  videoFrameStyle?: CSSProperties;
  isCompareActive: boolean;
  canAdjustView?: boolean;
  onFileSelected: (file: File) => void;
  onSeek: (time: number) => void;
  onSetSyncPoint: () => void;
  onClear: () => void;
  onViewTransformChange?: (transform: { scale: number; offsetX: number; offsetY: number }) => void;
}

export function VideoSlotPanel({
  slot,
  compact = false,
  children,
  videoFrameStyle,
  isCompareActive,
  canAdjustView = false,
  onFileSelected,
  onSeek,
  onSetSyncPoint,
  onClear,
  onViewTransformChange,
}: VideoSlotPanelProps): ReactElement {
  const inputRef = useRef<HTMLInputElement | null>(null);
  const gestureRef = useRef<{
    pointers: Map<number, { x: number; y: number }>;
    startDistance: number;
    startScale: number;
    startOffsetX: number;
    startOffsetY: number;
    lastPanX: number;
    lastPanY: number;
  }>({
    pointers: new Map(),
    startDistance: 0,
    startScale: 1,
    startOffsetX: 0,
    startOffsetY: 0,
    lastPanX: 0,
    lastPanY: 0,
  });
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

  function getPointerDistance(): number {
    const pointers = Array.from(gestureRef.current.pointers.values());
    if (pointers.length < 2) {
      return 0;
    }

    return Math.hypot(pointers[0].x - pointers[1].x, pointers[0].y - pointers[1].y);
  }

  function updateTransform(scale: number, offsetX: number, offsetY: number): void {
    const nextScale = clamp(scale, MIN_VIEW_SCALE, MAX_VIEW_SCALE);

    onViewTransformChange?.({
      scale: nextScale,
      offsetX: nextScale <= MIN_VIEW_SCALE ? 0 : offsetX,
      offsetY: nextScale <= MIN_VIEW_SCALE ? 0 : offsetY,
    });
  }

  function handleZoomIn(): void {
    updateTransform(slot.viewScale + VIEW_SCALE_STEP, slot.viewOffsetX, slot.viewOffsetY);
  }

  function handleZoomOut(): void {
    updateTransform(slot.viewScale - VIEW_SCALE_STEP, slot.viewOffsetX, slot.viewOffsetY);
  }

  function handleResetView(): void {
    updateTransform(MIN_VIEW_SCALE, 0, 0);
  }

  function handlePointerDown(event: PointerEvent<HTMLDivElement>): void {
    if (!canAdjustView || !slot.objectUrl) {
      return;
    }

    event.currentTarget.setPointerCapture(event.pointerId);
    gestureRef.current.pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });

    if (gestureRef.current.pointers.size === 1) {
      gestureRef.current.lastPanX = event.clientX;
      gestureRef.current.lastPanY = event.clientY;
    }

    if (gestureRef.current.pointers.size === 2) {
      gestureRef.current.startDistance = getPointerDistance();
      gestureRef.current.startScale = slot.viewScale;
      gestureRef.current.startOffsetX = slot.viewOffsetX;
      gestureRef.current.startOffsetY = slot.viewOffsetY;
    }
  }

  function handlePointerMove(event: PointerEvent<HTMLDivElement>): void {
    if (!canAdjustView || !gestureRef.current.pointers.has(event.pointerId)) {
      return;
    }

    gestureRef.current.pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });

    if (gestureRef.current.pointers.size >= 2) {
      event.preventDefault();
      const distance = getPointerDistance();
      if (gestureRef.current.startDistance <= 0 || distance <= 0) {
        return;
      }

      updateTransform(
        gestureRef.current.startScale * (distance / gestureRef.current.startDistance),
        gestureRef.current.startOffsetX,
        gestureRef.current.startOffsetY,
      );
      return;
    }

    if (slot.viewScale <= MIN_VIEW_SCALE) {
      return;
    }

    event.preventDefault();
    const deltaX = event.clientX - gestureRef.current.lastPanX;
    const deltaY = event.clientY - gestureRef.current.lastPanY;
    gestureRef.current.lastPanX = event.clientX;
    gestureRef.current.lastPanY = event.clientY;
    updateTransform(slot.viewScale, slot.viewOffsetX + deltaX, slot.viewOffsetY + deltaY);
  }

  function handlePointerUp(event: PointerEvent<HTMLDivElement>): void {
    if (!gestureRef.current.pointers.has(event.pointerId)) {
      return;
    }

    gestureRef.current.pointers.delete(event.pointerId);
    if (gestureRef.current.pointers.size === 1) {
      const pointer = Array.from(gestureRef.current.pointers.values())[0];
      gestureRef.current.lastPanX = pointer.x;
      gestureRef.current.lastPanY = pointer.y;
    }
  }

  const transformStyle: CSSProperties = {
    transform: `translate(${slot.viewOffsetX}px, ${slot.viewOffsetY}px) scale(${slot.viewScale})`,
  };
  const syncStatusText = slot.hasSyncPoint ? formatTime(slot.syncPointSec) : "未設定";

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
        <div
          className={`slot-panel__video ${canAdjustView && slot.objectUrl ? "is-view-adjustable" : ""}`}
          style={videoFrameStyle}
          onPointerDown={handlePointerDown}
          onPointerMove={handlePointerMove}
          onPointerUp={handlePointerUp}
          onPointerCancel={handlePointerUp}
        >
          <div className="slot-panel__video-transform" style={transformStyle}>
            {children}
          </div>
          {!isCompareActive && slot.objectUrl ? (
            <div
              className={`slot-panel__video-sync-badge ${slot.hasSyncPoint ? "is-set" : "is-unset"}`}
              aria-label={`${slot.label}の基準点は${syncStatusText}`}
            >
              {slot.hasSyncPoint ? (
                <CheckCircle2 size={16} aria-hidden="true" />
              ) : (
                <CircleDot size={16} aria-hidden="true" />
              )}
              <span>基準点</span>
              <strong>{syncStatusText}</strong>
            </div>
          ) : null}
          {canAdjustView && slot.objectUrl ? (
            <div
              className="view-zoom-controls"
              aria-label={`${slot.label}の表示調整`}
              onPointerDown={(event) => event.stopPropagation()}
              onPointerMove={(event) => event.stopPropagation()}
              onPointerUp={(event) => event.stopPropagation()}
              onPointerCancel={(event) => event.stopPropagation()}
            >
              <button
                type="button"
                className="icon-button"
                onClick={handleZoomOut}
                disabled={slot.viewScale <= MIN_VIEW_SCALE}
                aria-label={`${slot.label}を縮小`}
                title="縮小"
              >
                <Minus size={17} aria-hidden="true" />
              </button>
              <button
                type="button"
                className="icon-button"
                onClick={handleResetView}
                disabled={
                  slot.viewScale <= MIN_VIEW_SCALE && slot.viewOffsetX === 0 && slot.viewOffsetY === 0
                }
                aria-label={`${slot.label}の表示をリセット`}
                title="リセット"
              >
                <RotateCcw size={17} aria-hidden="true" />
              </button>
              <button
                type="button"
                className="icon-button"
                onClick={handleZoomIn}
                disabled={slot.viewScale >= MAX_VIEW_SCALE}
                aria-label={`${slot.label}を拡大`}
                title="拡大"
              >
                <Plus size={17} aria-hidden="true" />
              </button>
            </div>
          ) : null}
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
            <button
              type="button"
              className={`sync-point-button ${slot.hasSyncPoint ? "is-set" : ""}`}
              onClick={onSetSyncPoint}
              disabled={!slot.isReady}
            >
              {slot.hasSyncPoint ? (
                <CheckCircle2 size={17} aria-hidden="true" />
              ) : (
                <CircleDot size={17} aria-hidden="true" />
              )}
              {slot.hasSyncPoint ? "基準点設定済み" : "基準点を設定"}
            </button>
            <span className={`sync-readout ${slot.hasSyncPoint ? "is-set" : "is-unset"}`}>
              {syncStatusText}
            </span>
          </div>
        </div>
      ) : null}
    </section>
  );
}
