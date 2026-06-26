# Video Compare

スマホの写真ライブラリやPCのローカルファイルから2本の動画を選び、同期再生・スロー再生・区間ループ・重ね合わせで比較するスポーツ練習用Webアプリです。

## 開発

```bash
npm install
npm run dev
```

ローカルURL:

```text
http://localhost:5173/video-compare/
```

## ビルド

```bash
npm run build
```

## GitHub Pages

- リポジトリ名は `video-compare` を想定しています。
- Viteの `base` は `/video-compare/` に設定済みです。
- `main` ブランチへpushすると `.github/workflows/deploy.yml` でGitHub Pagesへ自動デプロイします。
- GitHub側の Pages source は `GitHub Actions` に設定してください。

## 動画データ

動画は `input type="file"` と `URL.createObjectURL()` で端末内から読み込みます。動画本体、選手データ、履歴はサーバーへ送信・保存しません。
