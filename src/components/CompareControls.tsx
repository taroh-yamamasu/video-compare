import {
  Maximize2,
  Pause,
  Play,
  Repeat,
  RotateCcw,
  SkipBack,
  SkipForward,
  SlidersHorizontal,
} from "lucide-react";
import type { ReactElement } from "react";
import type { CompareSettings } from "../types";
import { clamp, formatTime } from "../utils/time";

interface CompareControlsProps {
  settings: CompareSettings;
  isFitCompareActive: boolean;
  canStartFitCompare: boolean;
  timelineTime: number;
  timelineMin: number;
  timelineMax: number;
  bothReady: boolean;
  anyPlaying: boolean;
  onTogglePlayback: () => void;
  onSeek: (normalizedTime: number) => void;
  onStep: (direction: -1 | 1) => void;
  onPlaybackRateChange: (playbackRate: number) => void;
  onStepSecondsChange: (stepSeconds: number) => void;
  onToggleLoop: () => void;
  onMarkLoopStart: () => void;
  onMarkLoopEnd: () => void;
  onStartFitCompare: () => void;
  onExitFitCompare: () => void;
}

const PLAYBACK_RATES = [0.25, 0.5, 0.75, 1, 1.25] as const;

export function CompareControls({
  settings,
  isFitCompareActive,
  canStartFitCompare,
  timelineTime,
  timelineMin,
  timelineMax,
  bothReady,
  anyPlaying,
  onTogglePlayback,
  onSeek,
  onStep,
  onPlaybackRateChange,
  onStepSecondsChange,
  onToggleLoop,
  onMarkLoopStart,
  onMarkLoopEnd,
  onStartFitCompare,
  onExitFitCompare,
}: CompareControlsProps): ReactElement {
  const sliderMin = Number.isFinite(timelineMin) ? timelineMin : 0;
  const sliderMax = Number.isFinite(timelineMax) && timelineMax > sliderMin ? timelineMax : sliderMin + 1;
  const sliderValue = clamp(timelineTime, sliderMin, sliderMax);

  if (isFitCompareActive) {
    return (
      <section className="compare-controls compare-controls--active" aria-label="同期コントロール">
        <div className="compare-playback-controls">
          <button type="button" className="primary-control" onClick={onTogglePlayback} disabled={!bothReady}>
            {anyPlaying ? <Pause size={22} aria-hidden="true" /> : <Play size={22} aria-hidden="true" />}
            {anyPlaying ? "停止" : "再生"}
          </button>
          <div className="time-chip">{formatTime(timelineTime)}</div>
          <button type="button" className="secondary-control" onClick={onExitFitCompare}>
            <RotateCcw size={17} aria-hidden="true" />
            編集に戻る
          </button>
        </div>

        <div className="timeline-row timeline-row--compact">
          <span>{formatTime(sliderMin)}</span>
          <input
            type="range"
            min={sliderMin}
            max={sliderMax}
            step="0.001"
            value={sliderValue}
            disabled={!bothReady}
            onChange={(event) => onSeek(Number(event.currentTarget.value))}
            aria-label="同期タイムライン"
          />
          <span>{formatTime(sliderMax)}</span>
        </div>
      </section>
    );
  }

  return (
    <section className="compare-controls compare-controls--setup" aria-label="同期コントロール">
      <div className="setup-controls">
        <button type="button" className="fit-start-button" onClick={onStartFitCompare} disabled={!canStartFitCompare}>
          <Maximize2 size={18} aria-hidden="true" />
          比較開始
        </button>
        <label className="field field--rate">
          <span>速度</span>
          <select
            value={settings.playbackRate}
            onChange={(event) => onPlaybackRateChange(Number(event.currentTarget.value))}
          >
            {PLAYBACK_RATES.map((rate) => (
              <option key={rate} value={rate}>
                {rate}x
              </option>
            ))}
          </select>
        </label>
      </div>

      <details className="advanced-controls">
        <summary>
          <SlidersHorizontal size={17} aria-hidden="true" />
          詳細
        </summary>
        <div className="advanced-controls__body">
          <div className="advanced-step-controls" aria-label="フレーム送り">
            <button type="button" className="icon-button" onClick={() => onStep(-1)} disabled={!bothReady}>
              <SkipBack size={18} aria-hidden="true" />
            </button>
            <button type="button" className="icon-button" onClick={() => onStep(1)} disabled={!bothReady}>
              <SkipForward size={18} aria-hidden="true" />
            </button>
          </div>

          <label className="field">
            <span>フレーム幅</span>
            <input
              type="number"
              min="0.001"
              max="1"
              step="0.001"
              value={Number(settings.stepSeconds.toFixed(3))}
              onChange={(event) => onStepSecondsChange(Number(event.currentTarget.value))}
            />
          </label>

          <div className="loop-controls">
            <button
              type="button"
              onClick={onToggleLoop}
              disabled={!bothReady}
              className={settings.loopEnabled ? "is-active" : ""}
            >
              <Repeat size={17} aria-hidden="true" />
              ループ
            </button>
            <button type="button" onClick={onMarkLoopStart} disabled={!bothReady}>
              開始
            </button>
            <button type="button" onClick={onMarkLoopEnd} disabled={!bothReady}>
              終了
            </button>
            <span>
              {formatTime(settings.loopStartSec)} - {formatTime(settings.loopEndSec)}
            </span>
          </div>
        </div>
      </details>
    </section>
  );
}
