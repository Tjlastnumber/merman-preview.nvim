// OpenTUI's border definitions and text attribute bits, without its UI runtime.
export { BorderChars } from './opentui-border';
export const TextAttributes = { NONE: 0, BOLD: 1, DIM: 2, ITALIC: 4, UNDERLINE: 8, BLINK: 16, INVERSE: 32, HIDDEN: 64, STRIKETHROUGH: 128 };
// Unused by the grid API; esbuild removes styled-text conversion functions.
export const RGBA = undefined;
export const StyledText = undefined;
