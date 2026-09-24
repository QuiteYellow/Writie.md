import { EditorColors, EditorTheme } from '../types';
import { buildTheme, buildHighlight, tags } from '../builder';
import { lightBase as base } from './colors';

// Xcode 27 renders colours its Default (Light).xccolortheme no longer
// describes, the same way the dark theme does. These values come from
// DylanVann/xcode-system-theme, which reads them out of Xcode's live editor
// through the accessibility API — second-hand, unlike xcode-dark.ts, which was
// measured here. The two agreed to within 1/255 on 15 of 17 dark values, which
// is why they are trusted; a light measurement pass would still settle them.
const palette = {
  text: '#322529',
  // Xcode draws keywords and attributes in one colour, in both appearances.
  // Emphasis has no Swift counterpart and follows the attribute colour.
  pink: '#c4246e',
};

const colors: EditorColors = {
  accent: '#006279',
  text: palette.text,
  comment: '#6a7084',
  background: '#ffffff',
  caret: palette.text,
  selection: '#b3d7ff',
  activeLine: '#eeeeee',
  matchingBracket: '#00695c40',
  lineNumber: '#b8b3b4',
  // Not measured: Xcode's theme format has no key for these, and no probe
  // can show them. Carried over.
  searchMatch: '#e4e4e4',
  selectionHighlight: '#e9eef9',
  visibleSpace: '#cccccc',
  lighterBackground: '#cccccc4c',
};

function theme() {
  return buildTheme(colors);
}

function highlight() {
  // Order matters, don't change it unless you fully understand how it works
  return buildHighlight(colors, [
    { tag: [tags.keyword, tags.modifier, tags.operator, tags.operatorKeyword, tags.self], color: palette.pink },
    { tag: [tags.literal, tags.inserted], color: base.green },
    { tag: [tags.deleted, tags.macroName], color: base.red },
    { tag: [tags.className, tags.definition(tags.propertyName), tags.definition(tags.typeName)], color: '#00856f' },
    { tag: [tags.function(tags.variableName), tags.function(tags.propertyName)], color: '#8b0099' },
    { tag: [tags.meta, tags.comment], color: colors.comment, fontStyle: 'italic' },
    { tag: [tags.link, tags.escape, tags.string, tags.regexp, tags.special(tags.string)], color: '#ca2c1d' },
    { tag: [tags.linkMark, tags.listMark], color: '#0078b8' },
    { tag: tags.url, color: '#006279' },
    { tag: tags.propertyName, color: colors.text },
    { tag: tags.tagName, color: colors.accent },
    { tag: tags.attributeName, color: palette.pink },
    { tag: tags.definition(tags.variableName), color: '#00695c' },
    { tag: [tags.quote, tags.quoteMark], color: colors.comment, fontStyle: 'italic' },
    { tag: [tags.atom, tags.bool, tags.number], color: '#0078b8' },
    { tag: tags.emphasis, color: palette.pink, fontStyle: 'italic' },
    { tag: tags.strong, color: '#9d31cf', fontWeight: 'bolder' },
  ]);
}

export default function XcodeLight(): EditorTheme {
  return {
    colors,
    extension: [theme(), highlight()],
  };
}
