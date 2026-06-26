export function clamp(value: number, min: number, max: number): number {
  if (Number.isNaN(value)) {
    return min;
  }

  return Math.min(Math.max(value, min), max);
}

export function formatTime(seconds: number): string {
  if (!Number.isFinite(seconds)) {
    return "0:00.00";
  }

  const sign = seconds < 0 ? "-" : "";
  const absolute = Math.abs(seconds);
  const minutes = Math.floor(absolute / 60);
  const remaining = absolute - minutes * 60;
  const wholeSeconds = Math.floor(remaining);
  const hundredths = Math.floor((remaining - wholeSeconds) * 100);

  return `${sign}${minutes}:${wholeSeconds.toString().padStart(2, "0")}.${hundredths
    .toString()
    .padStart(2, "0")}`;
}

export function isLikelyVideoFile(file: File): boolean {
  const lowerName = file.name.toLowerCase();
  return file.type.startsWith("video/") || lowerName.endsWith(".mov") || lowerName.endsWith(".mp4");
}
