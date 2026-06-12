const fs = require("fs");
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  Header, Footer, AlignmentType, LevelFormat, HeadingLevel, BorderStyle,
  WidthType, ShadingType, PageNumber, PageBreak, TableOfContents,
} = require("docx");

const NAVY = "1E3A8A";
const BLUE = "2563EB";
const GREY = "64748B";
const LIGHT = "EEF2FF";
const GREEN = "16A34A";

const border = { style: BorderStyle.SINGLE, size: 1, color: "CCCCCC" };
const borders = { top: border, bottom: border, left: border, right: border };
const cellMargins = { top: 80, bottom: 80, left: 120, right: 120 };

// ---- helpers ----------------------------------------------------
function h1(text) {
  return new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun(text)] });
}
function h2(text) {
  return new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun(text)] });
}
function para(text, opts = {}) {
  return new Paragraph({
    spacing: { after: 120 },
    children: [new TextRun({ text, ...opts })],
  });
}
function bullet(text, bold = false) {
  return new Paragraph({
    numbering: { reference: "bullets", level: 0 },
    spacing: { after: 60 },
    children: [new TextRun({ text, bold })],
  });
}
function richBullet(runs) {
  return new Paragraph({
    numbering: { reference: "bullets", level: 0 },
    spacing: { after: 60 },
    children: runs,
  });
}

function headerCell(text, w) {
  return new TableCell({
    borders, width: { size: w, type: WidthType.DXA }, margins: cellMargins,
    shading: { fill: NAVY, type: ShadingType.CLEAR },
    children: [new Paragraph({ children: [new TextRun({ text, bold: true, color: "FFFFFF", size: 20 })] })],
  });
}
function cell(text, w, opts = {}) {
  return new TableCell({
    borders, width: { size: w, type: WidthType.DXA }, margins: cellMargins,
    shading: opts.fill ? { fill: opts.fill, type: ShadingType.CLEAR } : undefined,
    children: [new Paragraph({
      alignment: opts.align,
      children: [new TextRun({ text, bold: opts.bold || false, size: 20, color: opts.color })],
    })],
  });
}

function makeTable(widths, headerRow, rows) {
  const total = widths.reduce((a, b) => a + b, 0);
  const trs = [];
  trs.push(new TableRow({ tableHeader: true, children: headerRow.map((t, i) => headerCell(t, widths[i])) }));
  rows.forEach((r, ri) => {
    const fill = ri % 2 === 0 ? "F8FAFC" : "FFFFFF";
    trs.push(new TableRow({
      children: r.map((c, i) => {
        const isObj = typeof c === "object" && c !== null;
        const txt = isObj ? c.text : c;
        return cell(txt, widths[i], {
          fill: (isObj && c.fill) ? c.fill : fill,
          bold: isObj && c.bold,
          align: isObj && c.align,
          color: isObj && c.color,
        });
      }),
    }));
  });
  return new Table({ width: { size: total, type: WidthType.DXA }, columnWidths: widths, rows: trs });
}

const CW = 9360; // content width (US Letter, 1" margins)

// ---- document ---------------------------------------------------
const children = [];

// Title block
children.push(new Paragraph({
  spacing: { before: 2200, after: 0 }, alignment: AlignmentType.CENTER,
  children: [new TextRun({ text: "AI-Powered LMS", bold: true, size: 56, color: NAVY })],
}));
children.push(new Paragraph({
  alignment: AlignmentType.CENTER, spacing: { after: 60 },
  children: [new TextRun({ text: "Hybrid Video Generation — Cost Analysis & Approach", bold: true, size: 30, color: BLUE })],
}));
children.push(new Paragraph({
  alignment: AlignmentType.CENTER, spacing: { after: 40 },
  children: [new TextRun({ text: "Whiteboard Animation (Free) + HeyGen Avatar (Paid API)", size: 24, color: GREY })],
}));
children.push(new Paragraph({
  alignment: AlignmentType.CENTER, spacing: { before: 1600, after: 0 },
  children: [new TextRun({ text: "Prepared for: Project Stakeholders", size: 22, color: GREY })],
}));
children.push(new Paragraph({
  alignment: AlignmentType.CENTER, spacing: { after: 0 },
  children: [new TextRun({ text: "Date: 8 June 2026", size: 22, color: GREY })],
}));
children.push(new Paragraph({
  alignment: AlignmentType.CENTER, spacing: { after: 0 },
  children: [new TextRun({ text: "Status: Confidential — Internal", size: 22, color: GREY })],
}));
children.push(new Paragraph({ children: [new PageBreak()] }));

// TOC
children.push(h1("Table of Contents"));
children.push(new TableOfContents("Table of Contents", { hyperlink: true, headingStyleRange: "1-2" }));
children.push(new Paragraph({ children: [new PageBreak()] }));

// 1. Executive Summary
children.push(h1("1. Executive Summary"));
children.push(para(
  "This document defines a hybrid video-generation strategy for the AI-Powered Learning Management System (LMS). " +
  "The objective is to produce professional, multilingual safety-training videos at the lowest sustainable cost by combining a free, in-house animation engine with a paid avatar-video API used only where it adds genuine value."));
children.push(para("Key findings:", { bold: true }));
children.push(bullet("A 15-minute training course can be produced for approximately ₹360, and as little as ₹21 if no avatar footage is used."));
children.push(bullet("The only meaningful cost driver is paid avatar video (HeyGen). Every other component — scripting, narration, animation, icons, and encoding — is effectively free."));
children.push(bullet("Reusing intro/outro avatar clips across courses reduces the realistic per-course cost to roughly ₹190."));

// 2. Approach
children.push(h1("2. The Hybrid Approach"));
children.push(para(
  "Each course script is automatically split into two kinds of scenes. The system decides the layout, animations, " +
  "colours, and on-screen elements for every scene, then renders the final MP4."));
children.push(h2("2.1 Whiteboard Scenes (Free)"));
children.push(para("Generated entirely in-house. Used for the bulk of teaching content — concepts, bullet points, icons, callouts, and on-screen questions, animated in a hand-drawn whiteboard style with synchronised narration."));
children.push(h2("2.2 Avatar Scenes (Paid — HeyGen API)"));
children.push(para("A realistic human presenter on camera, generated via the HeyGen API. Reserved for the moments where a human face adds the most value: the introduction, key safety demonstrations, and the closing."));

children.push(h2("2.3 Production Pipeline"));
children.push(makeTable([700, 3200, 5460],
  ["Step", "Tool", "Role"],
  [
    ["1", "Claude (Haiku 4.5)", "Reads the script, plans scenes, decides layout / colours / animations"],
    ["2", "edge-tts (Microsoft)", "Generates neural narration voice + word timings (free)"],
    ["3", "Iconify API", "Supplies vector illustrations / icons (free)"],
    ["4", "Whiteboard engine", "Builds the animated HTML for teaching scenes (free)"],
    ["5", "HeyGen API", "Generates realistic avatar video for selected scenes (paid)"],
    ["6", "Playwright + FFmpeg", "Records animation and assembles the final MP4 (free)"],
  ]));

// 3. Pricing
children.push(new Paragraph({ children: [new PageBreak()] }));
children.push(h1("3. Verified Pricing"));
children.push(para("All rates below are taken from official published sources (see Section 7). Indian Rupee figures use an exchange rate of ₹85 per US Dollar.", { italics: true, color: GREY }));

children.push(h2("3.1 HeyGen API (Paid Video)"));
children.push(para("Billed pay-as-you-go in US dollars, with a $5 minimum and no monthly commitment. There is no free tier."));
children.push(makeTable([5460, 2000, 1900],
  ["HeyGen Video Type", "Cost (USD)", "Cost (INR)"],
  [
    [{ text: "Standard avatar (talking head, 720p/1080p)", bold: true }, { text: "$1.00 / min", align: AlignmentType.CENTER }, { text: "₹85 / min", align: AlignmentType.CENTER, bold: true }],
    ["Avatar IV (premium photorealistic)", { text: "$4.00 / min", align: AlignmentType.CENTER }, { text: "₹340 / min", align: AlignmentType.CENTER }],
    ["Video translation", { text: "$2.00 / min", align: AlignmentType.CENTER }, { text: "₹170 / min", align: AlignmentType.CENTER }],
  ]));

children.push(h2("3.2 Claude Haiku 4.5 (Scripting & Planning)"));
children.push(makeTable([5460, 2000, 1900],
  ["Token Type", "Cost (USD)", "Cost (INR)"],
  [
    ["Input tokens", { text: "$1.00 / million", align: AlignmentType.CENTER }, { text: "₹85 / M", align: AlignmentType.CENTER }],
    ["Output tokens", { text: "$5.00 / million", align: AlignmentType.CENTER }, { text: "₹425 / M", align: AlignmentType.CENTER }],
    ["Cached input (reused source)", { text: "$0.10 / million", align: AlignmentType.CENTER }, { text: "₹8.5 / M", align: AlignmentType.CENTER }],
  ]));

children.push(h2("3.3 Free Components"));
children.push(para("The following incur no per-use cost: edge-tts narration, Iconify illustrations, the whiteboard animation engine, Playwright recording, and FFmpeg encoding."));

// 4. Cost breakdown
children.push(new Paragraph({ children: [new PageBreak()] }));
children.push(h1("4. Cost of One 15-Minute Course"));
children.push(h2("4.1 Recommended Scene Split"));
children.push(makeTable([4100, 1300, 2160, 1800],
  ["Segment", "Minutes", "Engine", "Cost"],
  [
    ["Intro — presenter welcome on camera", { text: "1", align: AlignmentType.CENTER }, "HeyGen", { text: "$1.00", align: AlignmentType.CENTER }],
    ["Core teaching (concepts, bullets, icons)", { text: "~10", align: AlignmentType.CENTER }, { text: "Whiteboard", color: GREEN }, { text: "Free", align: AlignmentType.CENTER, color: GREEN }],
    ["2 key safety demonstrations", { text: "2", align: AlignmentType.CENTER }, "HeyGen", { text: "$2.00", align: AlignmentType.CENTER }],
    ["Outro — closing / call to action", { text: "1", align: AlignmentType.CENTER }, "HeyGen", { text: "$1.00", align: AlignmentType.CENTER }],
    ["Transitions & summaries", { text: "~1", align: AlignmentType.CENTER }, { text: "Whiteboard", color: GREEN }, { text: "Free", align: AlignmentType.CENTER, color: GREEN }],
    [{ text: "HeyGen total", bold: true, fill: LIGHT }, { text: "4", align: AlignmentType.CENTER, bold: true, fill: LIGHT }, { text: "", fill: LIGHT }, { text: "$4.00", align: AlignmentType.CENTER, bold: true, fill: LIGHT }],
  ]));

children.push(h2("4.2 Total Genuine Cost"));
children.push(makeTable([5060, 2300, 2000],
  ["Cost Item", "USD", "INR"],
  [
    ["Claude (full course generation, with caching)", { text: "~$0.25", align: AlignmentType.CENTER }, { text: "~₹21", align: AlignmentType.CENTER }],
    ["HeyGen (4 min standard avatar @ $1/min)", { text: "$4.00", align: AlignmentType.CENTER }, { text: "₹340", align: AlignmentType.CENTER }],
    ["edge-tts narration (all 15 min)", { text: "$0.00", align: AlignmentType.CENTER, color: GREEN }, { text: "₹0", align: AlignmentType.CENTER, color: GREEN }],
    ["Iconify, Playwright, FFmpeg", { text: "$0.00", align: AlignmentType.CENTER, color: GREEN }, { text: "₹0", align: AlignmentType.CENTER, color: GREEN }],
    [{ text: "TOTAL per 15-minute video", bold: true, fill: LIGHT }, { text: "~$4.25", align: AlignmentType.CENTER, bold: true, fill: LIGHT }, { text: "≈ ₹360", align: AlignmentType.CENTER, bold: true, fill: LIGHT }],
  ]));
children.push(para("The Claude cost is genuinely negligible. The entire meaningful cost is the four HeyGen minutes you choose to make “real.”", { italics: true, color: GREY }));

// 5. Cost reduction
children.push(h1("5. Cost-Reduction Levers"));
children.push(makeTable([5460, 3900],
  ["Lever", "Effect on the ₹360 baseline"],
  [
    ["Cut HeyGen to intro + outro only (2 min)", { text: "₹360 → ~₹190" }],
    ["Reuse intro/outro avatar clips across all courses", "One-time cost, amortised to ~₹0 per future course"],
    ["Use standard avatar, never Avatar IV", "Avoids the 4× premium rate"],
    ["Whiteboard-only (no HeyGen)", { text: "₹21 per video" }],
  ]));
children.push(para("Cost as a function of avatar minutes:", { bold: true }));
children.push(richBullet([new TextRun({ text: "4 HeyGen minutes → ", }), new TextRun({ text: "₹360", bold: true })]));
children.push(richBullet([new TextRun({ text: "2 HeyGen minutes → ", }), new TextRun({ text: "₹190", bold: true })]));
children.push(richBullet([new TextRun({ text: "0 HeyGen minutes → ", }), new TextRun({ text: "₹21", bold: true })]));

// 6. Recommendation
children.push(h1("6. Recommendation"));
children.push(para(
  "Adopt the hybrid model. Begin with the $5 HeyGen pay-as-you-go credit, which is enough to test roughly five courses’ worth of avatar footage."));
children.push(bullet("Generate the intro and outro avatar clips once per “instructor,” then reuse them across every course."));
children.push(bullet("Use the free whiteboard engine for all core teaching, which is the majority of every course."));
children.push(bullet("After initial setup, the realistic per-course cost settles at roughly ₹190–360."));
children.push(para(
  "The result looks like a paid platform: the human-on-camera bookends sell the production quality, while the inexpensive whiteboard engine carries the actual teaching.", { bold: true }));

// 7. Sources
children.push(h1("7. Sources"));
children.push(bullet("HeyGen API Pricing Explained — HeyGen Help Center (help.heygen.com)."));
children.push(bullet("HeyGen API Pricing page (heygen.com/en-in/api-pricing)."));
children.push(bullet("Claude Haiku 4.5 pricing — Anthropic, current: $1/M input, $5/M output, $0.10/M cached input."));
children.push(para("Exchange rate assumption: ₹85 = $1.00 USD. Actual cost will vary slightly with the prevailing rate.", { italics: true, color: GREY }));

// ---- assemble ---------------------------------------------------
const doc = new Document({
  creator: "AI-Powered LMS",
  title: "Hybrid Video Generation — Cost Analysis",
  styles: {
    default: { document: { run: { font: "Arial", size: 22, color: "1F2937" } } },
    paragraphStyles: [
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 30, bold: true, color: NAVY, font: "Arial" },
        paragraph: { spacing: { before: 320, after: 160 }, outlineLevel: 0,
          border: { bottom: { style: BorderStyle.SINGLE, size: 6, color: BLUE, space: 4 } } } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 25, bold: true, color: BLUE, font: "Arial" },
        paragraph: { spacing: { before: 220, after: 100 }, outlineLevel: 1 } },
    ],
  },
  numbering: {
    config: [
      { reference: "bullets", levels: [
        { level: 0, format: LevelFormat.BULLET, text: "•", alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 540, hanging: 280 } } } },
      ] },
    ],
  },
  sections: [{
    properties: { page: {
      size: { width: 12240, height: 15840 },
      margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 },
    } },
    footers: { default: new Footer({ children: [new Paragraph({
      alignment: AlignmentType.CENTER,
      children: [
        new TextRun({ text: "AI-Powered LMS  —  Hybrid Video Cost Analysis  —  Page ", size: 16, color: GREY }),
        new TextRun({ children: [PageNumber.CURRENT], size: 16, color: GREY }),
      ],
    })] }) },
    children,
  }],
});

Packer.toBuffer(doc).then((buf) => {
  fs.writeFileSync("Hybrid_Video_Cost_Analysis.docx", buf);
  console.log("WROTE Hybrid_Video_Cost_Analysis.docx");
});
