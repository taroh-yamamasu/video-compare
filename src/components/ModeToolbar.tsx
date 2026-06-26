import type { ReactElement } from "react";
import { Columns2, Layers, Lock, Rows3, Unlock } from "lucide-react";
import type { CompareSettings, LayoutMode } from "../types";

interface ModeToolbarProps {
  settings: CompareSettings;
  onToggleLock: () => void;
  onLayoutChange: (layoutMode: LayoutMode) => void;
}

export function ModeToolbar({ settings, onToggleLock, onLayoutChange }: ModeToolbarProps): ReactElement {
  return (
    <div className="mode-toolbar" aria-label="比較モード">
      <div className="segmented-control">
        <button
          type="button"
          className={settings.isLocked ? "is-active" : ""}
          onClick={onToggleLock}
          aria-pressed={settings.isLocked}
        >
          {settings.isLocked ? <Lock size={17} aria-hidden="true" /> : <Unlock size={17} aria-hidden="true" />}
          {settings.isLocked ? "ロック" : "個別"}
        </button>
      </div>
      <div className="segmented-control">
        <button
          type="button"
          className={settings.layoutMode === "side-by-side" ? "is-active" : ""}
          onClick={() => onLayoutChange("side-by-side")}
          aria-pressed={settings.layoutMode === "side-by-side"}
        >
          <Columns2 size={17} aria-hidden="true" />
          左右
        </button>
        <button
          type="button"
          className={settings.layoutMode === "stacked" ? "is-active" : ""}
          onClick={() => onLayoutChange("stacked")}
          aria-pressed={settings.layoutMode === "stacked"}
        >
          <Rows3 size={17} aria-hidden="true" />
          上下
        </button>
        <button
          type="button"
          className={settings.layoutMode === "overlay" ? "is-active" : ""}
          onClick={() => onLayoutChange("overlay")}
          aria-pressed={settings.layoutMode === "overlay"}
        >
          <Layers size={17} aria-hidden="true" />
          重ね
        </button>
      </div>
    </div>
  );
}
