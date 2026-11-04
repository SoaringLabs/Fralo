import type { Dictionary } from "./en"

export const ja: Dictionary = {
  meta: {
    title: "Fralo · Mac でスクリーンショットをまとめてフレームに",
    description:
      "Fralo は、フォルダいっぱいのスクリーンショットをスマートフォン、タブレット、ブラウザのフレームにまとめて収める、無料でオープンソースの Mac App です。透明 PNG でも背景付きでも書き出せます。すべて Mac の中で完結します。",
  },
  skip: "本文へスキップ",
  url: "fralo.app/ja",
  language: "言語",
  download: "ダウンロード",
  hero: {
    title: ["デザインに", "フレームを"],
    lead: "Fralo なら、複数のスクリーンショットをスマートフォンやタブレット、ブラウザのフレームでそろえられます。App Store のプロダクトページやリリース記事など、いろいろな場面で使えます。",
    cta: "Mac 版をダウンロード",
    meta: "無料・オープンソース · macOS 14 以降 · Apple シリコン",
    devices: "スマートフォン、タブレット、Safari ウインドウの書き出し例",
  },
  compare: {
    title: ["フレームを付けると？"],
    body: "スライダーを動かして、違いを見てみましょう",
    original: "元の画像",
    framed: "フレーム付き",
    label: "元の画像とフレーム付きの画像を比較",
  },
  canvases: {
    title: ["キャンバスを自分好みに"],
    body: "プリセットのキャンバスにデバイスを配置したり、背景をカスタマイズしたりできます。デバイスだけを透明背景で書き出すこともできます。",
    group: "キャンバスの比率",
    none: "なし",
    caption: "キャンバス {ratio} · ウォームテクスチャ",
    transparent: "透明 PNG · 余白 0 px",
  },
  workbench: {
    alt: "Fralo のワークベンチ：左に画像リスト、中央にライブプレビュー、右に設定",
    notes: [
      ["1 枚ずつではなく、まとめて。", "スクリーンショットやフォルダをドラッグするだけ。すべてに同じ設定が適用されます。"],
      ["位置は手で調整。", "プレビューでデバイスをドラッグするか、⌥ と矢印キーで 1 px ずつ動かせます。"],
      ["安心の書き出し。", "書き出すたびに新しいフォルダを作成し、元の画像は変更しません。1 枚失敗しても残りは書き出されます。"],
      ["すべてローカルで。", "アカウント不要、アップロードなし、解析なし。English、简体中文、繁體中文、日本語に対応。"],
    ],
  },
  cli: {
    title: ["同じ仕上がりを、1 コマンドで"],
    body: "AI エージェントに任せるのも簡単です。必要なのは 1 行のコマンドだけ。エージェントに必要な情報は、ここにそろっています。",
  },
  closing: {
    title: [["フレーム、", "キャンバス、", "書き出し。"], ["Mac アプリ", "ひとつで完結。"]],
  },
  inspector: {
    label: "このページ用の Fralo インスペクタ",
    browser: "ブラウザ",
    canvas: "キャンバス",
    window: "ウインドウ",
    shadow: "影",
    size: "サイズ",
    canvases: { texture: "テクスチャ", gradient: "グラデーション", clear: "透明", dark: "ダーク" },
    appearances: { light: "ライト", dark: "ダーク" },
    shadows: { none: "なし", soft: "薄い", strong: "濃い" },
    export: "このページを書き出す",
    exporting: "書き出し中…",
    exported: "1 枚の画像を {folder} に書き出しました。",
    tryIt: "スクリーンショットで試す",
    line: {
      window: "ブラウザウインドウ",
      canvas: "キャンバス",
      shadow: "影",
      wide: "px 幅 @2x",
    },
  },
  footer: {
    changelog: "更新履歴",
    license: "MIT ライセンス",
  },
}
