import { EditorColors, EditorTheme } from '../types';
import { buildTheme, buildHighlight, tags } from '../builder';
import { darkBase as base } from './colors';

// Measured from Xcode 27.0 (27A266a) as it actually renders, by sampling
// screenshots of a probe file, rather than read out of its shipped
// Default (Dark).xccolortheme. Xcode 27 no longer paints the values in that
// file: it declares #1f1f24 for the editor background and Xcode draws #262626,
// and every syntax colour has moved with it.
const palette = {
  text: '#faf1f3',
  // Xcode draws keywords and attributes in one colour. Markdown has no Swift
  // counterpart for emphasis, so italics follow the attribute colour rather
  // than keep the old brown, which Xcode 27 no longer draws anywhere.
  pink: '#ff82b3',
};

const colors: EditorColors = {
  accent: '#00cafa',
  text: palette.text,
  comment: '#aab3cd',
  background: '#262626',
  caret: palette.text,
  selection: '#205093',
  activeLine: '#353535',
  matchingBracket: '#21ad9c40',
  lineNumber: '#6f6d6e',
  // Not measured: Xcode's theme format has no key for these and the probe
  // could not show them. Carried over.
  searchMatch: '#545558',
  selectionHighlight: '#4d5465',
  visibleSpace: '#888888',
  lighterBackground: '#88888840',
};

function theme() {
  return buildTheme(colors, 'dark');
}

function highlight() {
  // Order matters, don't change it unless you fully understand how it works
  return buildHighlight(colors, [
    { tag: [tags.keyword, tags.modifier, tags.operator, tags.operatorKeyword, tags.self], color: palette.pink },
    { tag: [tags.literal, tags.inserted], color: base.green },
    { tag: [tags.deleted, tags.macroName], color: base.red },
    { tag: [tags.className, tags.definition(tags.propertyName), tags.definition(tags.typeName)], color: '#00d9b2' },
    { tag: [tags.function(tags.variableName), tags.function(tags.propertyName)], color: '#d852e6' },
    { tag: [tags.meta, tags.comment], color: colors.comment, fontStyle: 'italic' },
    { tag: [tags.link, tags.escape, tags.string, tags.regexp, tags.special(tags.string)], color: '#ff8d7a' },
    { tag: [tags.linkMark, tags.listMark], color: '#eba800' },
    { tag: tags.url, color: '#27a6c1' },
    { tag: tags.propertyName, color: colors.text },
    { tag: tags.tagName, color: colors.accent },
    { tag: tags.attributeName, color: palette.pink },
    { tag: tags.definition(tags.variableName), color: '#21ad9c' },
    { tag: [tags.quote, tags.quoteMark], color: '#d3d3e0', fontStyle: 'italic' },
    { tag: [tags.atom, tags.bool, tags.number], color: '#eba800' },
    { tag: tags.emphasis, color: palette.pink, fontStyle: 'italic' },
    { tag: tags.strong, color: '#d896fe', fontWeight: 'bolder' },
  ], 'dark');
}

export default function XcodeDark(): EditorTheme {
  return {
    colors,
    extension: [theme(), highlight()],
  };
}
