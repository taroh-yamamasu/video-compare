import { useEffect, useMemo, useRef, useState } from "react";
import type { ReactElement } from "react";
import { CompareControls } from "./components/CompareControls";
import { ModeToolbar } from "./components/ModeToolbar";
import { OverlayStage } from "./components/OverlayStage";
import { VideoPlayer } from "./components/VideoPlayer";
import { VideoSlotPanel } from "./components/VideoSlotPanel";
import { DEFAULT_COMPARE_SETTINGS, DEFAULT_OVERLAY_SETTINGS, createInitialSlot } from "./constants";
import { loadPersistedSettings, savePersistedSettings, toPersistedSettings } from "./storage";
import type { CompareSettings, LayoutMode, OverlaySettings, SlotId, VideoSlotState } from "./types";
import { clamp, isLikelyVideoFile } from "./utils/time";

type SlotsState = Record<SlotId, VideoSlotState>;

const SLOT_IDS: SlotId[] = ["left", "right"];

function getInitialCompareDefaults(): CompareSettings {
  return {
    ...DEFAULT_COMPARE_SETTINGS,
    layoutMode: DEFAULT_COMPARE_SETTINGS.layoutMode,
  };
}

function getInitialCompareSettings(): CompareSettings {
  const compareDefaults = getInitialCompareDefaults();
  const persisted = loadPersistedSettings(compareDefaults, DEFAULT_OVERLAY_SETTINGS);
  const isMobile = typeof window !== "undefined" && window.innerWidth <= 760;
  const layoutMode = isMobile && persisted.layoutMode === "stacked" ? "side-by-side" : persisted.layoutMode;

  return {
    ...compareDefaults,
    isLocked: persisted.isLocked,
    layoutMode,
    playbackRate: persisted.playbackRate,
    stepSeconds: persisted.stepSeconds,
  };
}

function getInitialOverlaySettings(): OverlaySettings {
  const persisted = loadPersistedSettings(getInitialCompareDefaults(), DEFAULT_OVERLAY_SETTINGS);
  return persisted.overlay;
}

function getTimelineBounds(slots: SlotsState): { min: number; max: number } {
  const left = slots.left;
  const right = slots.right;

  if (!left.isReady || !right.isReady) {
    return { min: 0, max: 1 };
  }

  const min = Math.max(-left.syncPointSec, -right.syncPointSec);
  const max = Math.min(left.duration - left.syncPointSec, right.duration - right.syncPointSec);

  if (!Number.isFinite(max) || max <= min) {
    return { min: 0, max: Math.max(left.duration, right.duration, 1) };
  }

  return { min, max };
}

function areBothReady(slots: SlotsState): boolean {
  return slots.left.isReady && slots.right.isReady;
}

export function App(): ReactElement {
  const leftVideoRef = useRef<HTMLVideoElement | null>(null);
  const rightVideoRef = useRef<HTMLVideoElement | null>(null);
  const objectUrlsRef = useRef<Set<string>>(new Set());

  const [slots, setSlots] = useState<SlotsState>({
    left: createInitialSlot("left"),
    right: createInitialSlot("right"),
  });
  const [settings, setSettings] = useState<CompareSettings>(() => getInitialCompareSettings());
  const [overlay, setOverlay] = useState<OverlaySettings>(() => getInitialOverlaySettings());
  const [timelineTime, setTimelineTime] = useState(0);

  const slotsRef = useRef(slots);
  const settingsRef = useRef(settings);

  const bothReady = areBothReady(slots);
  const anyPlaying = slots.left.isPlaying || slots.right.isPlaying;
  const timelineBounds = useMemo(() => getTimelineBounds(slots), [slots]);

  useEffect(() => {
    slotsRef.current = slots;
  }, [slots]);

  useEffect(() => {
    settingsRef.current = settings;
    for (const id of SLOT_IDS) {
      const video = getVideo(id);
      if (video) {
        video.playbackRate = settings.playbackRate;
      }
    }
  }, [settings]);

  useEffect(() => {
    savePersistedSettings(toPersistedSettings(settings, overlay));
  }, [settings, overlay]);

  useEffect(() => {
    return () => {
      for (const objectUrl of objectUrlsRef.current) {
        URL.revokeObjectURL(objectUrl);
      }
      objectUrlsRef.current.clear();
    };
  }, []);

  useEffect(() => {
    let frameId = 0;

    function tick(): void {
      const currentSlots = slotsRef.current;
      const currentSettings = settingsRef.current;

      if (currentSettings.isLocked && areBothReady(currentSlots)) {
        const masterId: SlotId = currentSlots.left.isReady ? "left" : "right";
        const masterVideo = getVideo(masterId);

        if (masterVideo && !masterVideo.paused && !masterVideo.ended) {
          let normalized = masterVideo.currentTime - currentSlots[masterId].syncPointSec;

          if (
            currentSettings.loopEnabled &&
            currentSettings.loopEndSec > currentSettings.loopStartSec &&
            normalized >= currentSettings.loopEndSec
          ) {
            normalized = currentSettings.loopStartSec;
            seekNormalized(normalized);
          } else {
            setTimelineTime(normalized);
          }

          for (const id of SLOT_IDS) {
            if (id === masterId || !currentSlots[id].isReady) {
              continue;
            }

            const video = getVideo(id);
            if (!video) {
              continue;
            }

            const desiredTime = getActualTime(id, normalized, currentSlots);
            if (Math.abs(video.currentTime - desiredTime) > 0.09) {
              video.currentTime = desiredTime;
            }
          }
        }
      }

      frameId = window.requestAnimationFrame(tick);
    }

    frameId = window.requestAnimationFrame(tick);
    return () => window.cancelAnimationFrame(frameId);
  }, []);

  function patchSlot(id: SlotId, patch: Partial<VideoSlotState>): void {
    setSlots((previous) => {
      const next = {
        ...previous,
        [id]: {
          ...previous[id],
          ...patch,
        },
      };
      slotsRef.current = next;
      return next;
    });
  }

  function replaceSlot(id: SlotId, nextSlot: VideoSlotState): void {
    setSlots((previous) => {
      const next = {
        ...previous,
        [id]: nextSlot,
      };
      slotsRef.current = next;
      return next;
    });
  }

  function getVideo(id: SlotId): HTMLVideoElement | null {
    return id === "left" ? leftVideoRef.current : rightVideoRef.current;
  }

  function getActualTime(id: SlotId, normalizedTime: number, sourceSlots = slotsRef.current): number {
    const slot = sourceSlots[id];
    return clamp(normalizedTime + slot.syncPointSec, 0, slot.duration || 0);
  }

  function setActualTime(id: SlotId, actualTime: number): void {
    const slot = slotsRef.current[id];
    const nextTime = clamp(actualTime, 0, slot.duration || actualTime);
    const video = getVideo(id);

    if (video) {
      video.currentTime = nextTime;
    }

    patchSlot(id, { currentTime: nextTime });
  }

  function seekNormalized(normalizedTime: number): void {
    const currentSlots = slotsRef.current;
    const bounds = getTimelineBounds(currentSlots);
    const nextTime = clamp(normalizedTime, bounds.min, bounds.max);

    for (const id of SLOT_IDS) {
      if (currentSlots[id].isReady) {
        setActualTime(id, getActualTime(id, nextTime, currentSlots));
      }
    }

    setTimelineTime(nextTime);
  }

  function pauseVideos(): void {
    for (const id of SLOT_IDS) {
      const video = getVideo(id);
      if (video) {
        video.pause();
      }
    }
  }

  async function playVideos(): Promise<void> {
    if (!areBothReady(slotsRef.current)) {
      return;
    }

    for (const id of SLOT_IDS) {
      const video = getVideo(id);
      if (video) {
        video.playbackRate = settingsRef.current.playbackRate;
      }
    }

    await Promise.allSettled(SLOT_IDS.map((id) => getVideo(id)?.play()));
  }

  function handleFileSelected(id: SlotId, file: File): void {
    const existingUrl = slotsRef.current[id].objectUrl;
    getVideo(id)?.pause();

    if (!isLikelyVideoFile(file)) {
      patchSlot(id, {
        error: "動画ファイルを選んでください。",
        isReady: false,
        isPlaying: false,
      });
      return;
    }

    if (existingUrl) {
      URL.revokeObjectURL(existingUrl);
      objectUrlsRef.current.delete(existingUrl);
    }

    const objectUrl = URL.createObjectURL(file);
    objectUrlsRef.current.add(objectUrl);

    replaceSlot(id, {
      ...createInitialSlot(id),
      fileName: file.name,
      objectUrl,
    });
    setTimelineTime(0);
  }

  function handleClearSlot(id: SlotId): void {
    const existingUrl = slotsRef.current[id].objectUrl;
    getVideo(id)?.pause();

    if (existingUrl) {
      URL.revokeObjectURL(existingUrl);
      objectUrlsRef.current.delete(existingUrl);
    }

    replaceSlot(id, createInitialSlot(id));
    setTimelineTime(0);
  }

  function handleLoadedMetadata(id: SlotId, duration: number): void {
    patchSlot(id, {
      duration,
      isReady: Number.isFinite(duration) && duration > 0,
      error: Number.isFinite(duration) && duration > 0 ? null : "動画の長さを読み取れませんでした。",
    });
  }

  function handleTimeUpdate(id: SlotId, time: number): void {
    patchSlot(id, { currentTime: time });

    const slot = slotsRef.current[id];
    if (id === "left" || !slotsRef.current.left.isReady) {
      setTimelineTime(time - slot.syncPointSec);
    }
  }

  function handlePlayingChange(id: SlotId, isPlaying: boolean): void {
    patchSlot(id, { isPlaying });
  }

  function handleVideoError(id: SlotId, message: string): void {
    patchSlot(id, {
      error: message,
      isReady: false,
      isPlaying: false,
    });
  }

  function handleSlotSeek(id: SlotId, actualTime: number): void {
    const slot = slotsRef.current[id];
    const normalized = actualTime - slot.syncPointSec;

    if (settingsRef.current.isLocked && areBothReady(slotsRef.current)) {
      seekNormalized(normalized);
      return;
    }

    setActualTime(id, actualTime);
    setTimelineTime(normalized);
  }

  function handleSetSyncPoint(id: SlotId): void {
    const video = getVideo(id);
    const currentTime = video?.currentTime ?? slotsRef.current[id].currentTime;
    patchSlot(id, { syncPointSec: currentTime });
    setTimelineTime(0);
  }

  function handleSlotStep(id: SlotId, direction: number): void {
    if (!slotsRef.current[id].isReady) {
      return;
    }

    setActualTime(id, slotsRef.current[id].currentTime + direction * settingsRef.current.stepSeconds);
  }

  async function handleToggleSoloPlay(id: SlotId): Promise<void> {
    const video = getVideo(id);
    if (!video || !slotsRef.current[id].isReady) {
      return;
    }

    if (!video.paused) {
      video.pause();
      return;
    }

    video.playbackRate = settingsRef.current.playbackRate;
    await video.play().catch(() => undefined);
  }

  async function handleTogglePlayback(): Promise<void> {
    if (anyPlaying) {
      pauseVideos();
      return;
    }

    seekNormalized(timelineTime);
    await playVideos();
  }

  function handleTimelineStep(direction: -1 | 1): void {
    seekNormalized(timelineTime + direction * settingsRef.current.stepSeconds);
  }

  function handlePlaybackRateChange(playbackRate: number): void {
    if (!Number.isFinite(playbackRate) || playbackRate <= 0) {
      return;
    }

    setSettings((previous) => ({
      ...previous,
      playbackRate,
    }));
  }

  function handleStepSecondsChange(stepSeconds: number): void {
    setSettings((previous) => ({
      ...previous,
      stepSeconds: clamp(stepSeconds, 0.001, 1),
    }));
  }

  function handleToggleLoop(): void {
    setSettings((previous) => ({
      ...previous,
      loopEnabled: !previous.loopEnabled,
    }));
  }

  function handleMarkLoopStart(): void {
    setSettings((previous) => {
      const loopStartSec = timelineTime;
      return {
        ...previous,
        loopStartSec,
        loopEndSec: previous.loopEndSec <= loopStartSec ? loopStartSec + previous.stepSeconds : previous.loopEndSec,
      };
    });
  }

  function handleMarkLoopEnd(): void {
    setSettings((previous) => {
      const loopEndSec = timelineTime;
      return {
        ...previous,
        loopStartSec: previous.loopStartSec >= loopEndSec ? loopEndSec - previous.stepSeconds : previous.loopStartSec,
        loopEndSec,
      };
    });
  }

  function handleToggleLock(): void {
    setSettings((previous) => ({
      ...previous,
      isLocked: !previous.isLocked,
    }));
  }

  function handleLayoutChange(layoutMode: LayoutMode): void {
    pauseVideos();
    setSettings((previous) => ({
      ...previous,
      layoutMode,
    }));
  }

  function renderVideoSlot(id: SlotId): ReactElement {
    const videoRef = id === "left" ? leftVideoRef : rightVideoRef;

    return (
      <VideoSlotPanel
        key={id}
        slot={slots[id]}
        isLocked={settings.isLocked}
        canUseIndividualControls={!settings.isLocked}
        onFileSelected={(file) => handleFileSelected(id, file)}
        onSeek={(time) => handleSlotSeek(id, time)}
        onSetSyncPoint={() => handleSetSyncPoint(id)}
        onClear={() => handleClearSlot(id)}
        onStep={(direction) => handleSlotStep(id, direction)}
        onToggleSoloPlay={() => void handleToggleSoloPlay(id)}
      >
        <VideoPlayer
          slot={slots[id]}
          videoRef={videoRef}
          playbackRate={settings.playbackRate}
          className="video-element"
          onLoadedMetadata={(duration) => handleLoadedMetadata(id, duration)}
          onTimeUpdate={(time) => handleTimeUpdate(id, time)}
          onPlayingChange={(isPlaying) => handlePlayingChange(id, isPlaying)}
          onError={(message) => handleVideoError(id, message)}
        />
      </VideoSlotPanel>
    );
  }

  return (
    <div className={`app-shell app-shell--${settings.layoutMode}`}>
      <header className="app-header">
        <div>
          <h1>Video Compare</h1>
          <p>動画は外部送信されません</p>
        </div>
        <ModeToolbar settings={settings} onToggleLock={handleToggleLock} onLayoutChange={handleLayoutChange} />
      </header>

      <main className="app-main">
        {settings.layoutMode === "overlay" ? (
          <>
            <OverlayStage
              leftSlot={slots.left}
              rightSlot={slots.right}
              leftVideoRef={leftVideoRef}
              rightVideoRef={rightVideoRef}
              playbackRate={settings.playbackRate}
              overlay={overlay}
              onOverlayChange={setOverlay}
              onLoadedMetadata={handleLoadedMetadata}
              onTimeUpdate={handleTimeUpdate}
              onPlayingChange={handlePlayingChange}
              onVideoError={handleVideoError}
            />
            <div className="overlay-slot-controls">
              {SLOT_IDS.map((id) => (
                <VideoSlotPanel
                  key={id}
                  compact
                  slot={slots[id]}
                  isLocked={settings.isLocked}
                  canUseIndividualControls={!settings.isLocked}
                  onFileSelected={(file) => handleFileSelected(id, file)}
                  onSeek={(time) => handleSlotSeek(id, time)}
                  onSetSyncPoint={() => handleSetSyncPoint(id)}
                  onClear={() => handleClearSlot(id)}
                  onStep={(direction) => handleSlotStep(id, direction)}
                  onToggleSoloPlay={() => void handleToggleSoloPlay(id)}
                />
              ))}
            </div>
          </>
        ) : (
          <div className={`video-grid video-grid--${settings.layoutMode}`}>{SLOT_IDS.map(renderVideoSlot)}</div>
        )}

        <CompareControls
          settings={settings}
          timelineTime={timelineTime}
          timelineMin={timelineBounds.min}
          timelineMax={timelineBounds.max}
          bothReady={bothReady}
          anyPlaying={anyPlaying}
          onTogglePlayback={() => void handleTogglePlayback()}
          onSeek={seekNormalized}
          onStep={handleTimelineStep}
          onPlaybackRateChange={handlePlaybackRateChange}
          onStepSecondsChange={handleStepSecondsChange}
          onToggleLoop={handleToggleLoop}
          onMarkLoopStart={handleMarkLoopStart}
          onMarkLoopEnd={handleMarkLoopEnd}
        />
      </main>
    </div>
  );
}
