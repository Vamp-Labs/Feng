import type { CSSProperties } from "react";

export const wordIndex = (index: number) => ({ "--i": index }) as CSSProperties;

export function Words({ text, accent }: { text: string; accent?: string }) {
  const words = text.split(" ");
  return (
    <>
      {words.map((word, index) => (
        <span key={`${word}-${index}`}>
          <span className="word-mask">
            <span className={word === accent ? "word accent-word" : "word"} data-word style={wordIndex(index)}>
              {word}
            </span>
          </span>
          {index < words.length - 1 ? " " : null}
        </span>
      ))}
    </>
  );
}
