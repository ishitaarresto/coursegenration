const fs = require("fs");
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  Footer, AlignmentType, LevelFormat, HeadingLevel, BorderStyle,
  WidthType, ShadingType, PageNumber, PageBreak, TableOfContents,
} = require("docx");

const NAVY = "1E3A8A", BLUE = "2563EB", GREY = "64748B", LIGHT = "EEF2FF", GREEN = "16A34A", AMBER = "B45309";
const border = { style: BorderStyle.SINGLE, size: 1, color: "CCCCCC" };
const borders = { top: border, bottom: border, left: border, right: border };
const cm = { top: 80, bottom: 80, left: 120, right: 120 };

function h1(t){return new Paragraph({heading:HeadingLevel.HEADING_1,children:[new TextRun(t)]});}
function h2(t){return new Paragraph({heading:HeadingLevel.HEADING_2,children:[new TextRun(t)]});}
function p(t,o={}){return new Paragraph({spacing:{after:120},children:[new TextRun({text:t,...o})]});}
function b(t,bold=false){return new Paragraph({numbering:{reference:"bullets",level:0},spacing:{after:60},children:[new TextRun({text:t,bold})]});}
function hc(t,w){return new TableCell({borders,width:{size:w,type:WidthType.DXA},margins:cm,shading:{fill:NAVY,type:ShadingType.CLEAR},children:[new Paragraph({children:[new TextRun({text:t,bold:true,color:"FFFFFF",size:20})]})]});}
function c(t,w,o={}){return new TableCell({borders,width:{size:w,type:WidthType.DXA},margins:cm,shading:o.fill?{fill:o.fill,type:ShadingType.CLEAR}:undefined,children:[new Paragraph({alignment:o.align,children:[new TextRun({text:t,bold:o.bold||false,size:20,color:o.color})]})]});}
function tbl(widths,head,rows){
  const total=widths.reduce((a,x)=>a+x,0);
  const trs=[new TableRow({tableHeader:true,children:head.map((t,i)=>hc(t,widths[i]))})];
  rows.forEach((r,ri)=>{const f=ri%2===0?"F8FAFC":"FFFFFF";
    trs.push(new TableRow({children:r.map((cc,i)=>{const o=typeof cc==="object"&&cc!==null;const tx=o?cc.text:cc;
      return c(tx,widths[i],{fill:(o&&cc.fill)?cc.fill:f,bold:o&&cc.bold,align:o&&cc.align,color:o&&cc.color});})}));});
  return new Table({width:{size:total,type:WidthType.DXA},columnWidths:widths,rows:trs});
}
const CTR=AlignmentType.CENTER;
const children=[];

// Cover
children.push(new Paragraph({spacing:{before:2000,after:0},alignment:CTR,children:[new TextRun({text:"AI-Powered LMS",bold:true,size:56,color:NAVY})]}));
children.push(new Paragraph({alignment:CTR,spacing:{after:60},children:[new TextRun({text:"Generative Video Cost Analysis",bold:true,size:30,color:BLUE})]}));
children.push(new Paragraph({alignment:CTR,spacing:{after:40},children:[new TextRun({text:"Whiteboard Animation (Free) + AI Scene Video (Runway / Kling / Veo)",size:23,color:GREY})]}));
children.push(new Paragraph({alignment:CTR,spacing:{after:0},children:[new TextRun({text:"Real generated footage — driving, helmets, hazards, demonstrations",size:21,color:GREY,italics:true})]}));
children.push(new Paragraph({alignment:CTR,spacing:{before:1500,after:0},children:[new TextRun({text:"Prepared for: Project Stakeholders",size:22,color:GREY})]}));
children.push(new Paragraph({alignment:CTR,children:[new TextRun({text:"Date: 8 June 2026   |   Exchange rate: ₹85 = $1",size:22,color:GREY})]}));
children.push(new Paragraph({alignment:CTR,children:[new TextRun({text:"Status: Confidential — Internal",size:22,color:GREY})]}));
children.push(new Paragraph({children:[new PageBreak()]}));

// TOC
children.push(h1("Table of Contents"));
children.push(new TableOfContents("Table of Contents",{hyperlink:true,headingStyleRange:"1-2"}));
children.push(new Paragraph({children:[new PageBreak()]}));

// 1 Important correction
children.push(h1("1. Important Correction & Summary"));
children.push(p("An earlier estimate assumed talking-head avatar video (HeyGen). This document corrects that: realistic scenes such as a person driving a car, putting on a helmet, or demonstrating a hazard require GENERATIVE (text-to-video) models — Runway, Kling, or Google Veo — not avatars."));
children.push(p("These models bill PER SECOND, not per minute, and produce short clips (typically 5–8 seconds). Generated video is therefore expensive per minute (roughly ₹255–₹765 per minute), so it is used only for short, high-impact B-roll clips while the free in-house whiteboard engine carries the bulk of the teaching.",{}));
children.push(p("Headline result for a 15-minute course (≈ 60 seconds of generated B-roll + free whiteboard + free voiceover):",{bold:true}));
children.push(b("Budget (Runway Gen-4 Turbo): ≈ ₹276 per course"));
children.push(b("Mid quality (Kling 3.0): ≈ ₹531 per course"));
children.push(b("Premium realistic (Veo 3.1 Fast): ≈ ₹786 per course"));
children.push(p("Cost scales directly with seconds of generated video. The free whiteboard engine and free edge-tts voiceover keep everything else at near-zero.",{italics:true,color:GREY}));

// 2 How it works
children.push(h1("2. How the Hybrid Works"));
children.push(b("Whiteboard scenes (FREE): the majority of every course — concepts, bullets, icons, on-screen questions — animated in-house with synchronised narration.",true));
children.push(b("Generated B-roll clips (PAID, per second): short realistic clips for key moments — e.g. a driver fastening a seatbelt, a worker in a helmet, a hazard scenario.",true));
children.push(b("Voiceover (FREE): edge-tts narration is overlaid on top of all clips, so the video models' built-in audio is not required — letting us use the cheaper no-audio tiers.",true));
children.push(b("Scripting & planning (Claude): negligible cost, ~₹21 per full course.",true));

// 3 Verified per-second pricing
children.push(new Paragraph({children:[new PageBreak()]}));
children.push(h1("3. Verified Per-Second Pricing"));
children.push(p("All rates are from official developer documentation and current pricing pages (see Sources). Rupee values use ₹85 = $1.",{italics:true,color:GREY}));
children.push(tbl([3200,1900,1400,1400,1460],
  ["Model","Quality","$/sec","₹/sec","Built-in audio"],
  [
    [{text:"Runway Gen-4 Turbo",bold:true},"Good",{text:"$0.05",align:CTR},{text:"₹4.25",align:CTR,bold:true},{text:"No",align:CTR}],
    [{text:"Kling 3.0",bold:true},"Excellent",{text:"$0.10",align:CTR},{text:"₹8.50",align:CTR,bold:true},{text:"No",align:CTR}],
    [{text:"Veo 3.1 Fast",bold:true},"Excellent / realistic",{text:"$0.15",align:CTR},{text:"₹12.75",align:CTR,bold:true},{text:"Yes",align:CTR}],
    ["Runway Gen-4 (full)","High",{text:"$0.12",align:CTR},{text:"₹10.20",align:CTR},{text:"No",align:CTR}],
    ["Veo 3.1 Standard","Top-tier",{text:"$0.40",align:CTR},{text:"₹34.00",align:CTR},{text:"Yes",align:CTR}],
  ]));
children.push(p("Because we overlay our own free narration, the no-audio tiers (Runway Gen-4 Turbo, Kling 3.0) are the recommended workhorses.",{}));

children.push(h2("3.1 Cost Per Clip (6-second clip)"));
children.push(tbl([4000,2680,2680],
  ["Model","Per 6-sec clip (USD)","Per 6-sec clip (₹)"],
  [
    [{text:"Runway Gen-4 Turbo",bold:true},{text:"$0.30",align:CTR},{text:"₹26",align:CTR,bold:true}],
    [{text:"Kling 3.0",bold:true},{text:"$0.60",align:CTR},{text:"₹51",align:CTR,bold:true}],
    [{text:"Veo 3.1 Fast",bold:true},{text:"$0.90",align:CTR},{text:"₹77",align:CTR,bold:true}],
  ]));
children.push(p("Note: most models cap a single clip at ~5–10 seconds, so a “scene” is one short clip. Longer scenes = multiple clips stitched together.",{italics:true,color:GREY}));

children.push(h2("3.2 Claude (Scripting & Scene Planning)"));
children.push(p("Claude Haiku 4.5: $1.00 / million input tokens, $5.00 / million output tokens, $0.10 / million cached input. A full 15-minute course generation costs approximately $0.25 (≈ ₹21). This is an estimate based on typical token volumes, not a per-course meter, but even at 3× it stays under ₹65 — negligible against the video cost."));

// 4 Cost of a 15-min course
children.push(new Paragraph({children:[new PageBreak()]}));
children.push(h1("4. Cost of One 15-Minute Course"));
children.push(p("Assumes ~12 minutes of free whiteboard teaching, free edge-tts voiceover throughout, plus a chosen amount of generated B-roll. Claude (~₹21) is included in every figure below."));

children.push(h2("4.1 By Amount of Generated B-roll"));
children.push(tbl([3000,2120,2120,2120],
  ["Generated B-roll","Runway Turbo","Kling 3.0","Veo 3.1 Fast"],
  [
    ["30 sec (≈ 5 clips)",{text:"₹149",align:CTR},{text:"₹276",align:CTR},{text:"₹404",align:CTR}],
    [{text:"60 sec (≈ 10 clips)",bold:true,fill:LIGHT},{text:"₹276",align:CTR,bold:true,fill:LIGHT},{text:"₹531",align:CTR,bold:true,fill:LIGHT},{text:"₹786",align:CTR,bold:true,fill:LIGHT}],
    ["120 sec (≈ 20 clips)",{text:"₹531",align:CTR},{text:"₹1,041",align:CTR},{text:"₹1,551",align:CTR}],
  ]));
children.push(p("The 60-second row is the recommended balance: enough realistic footage to elevate the course, while the free whiteboard handles the other ~12 minutes.",{bold:true}));

children.push(h2("4.2 Worked Example — 60 sec B-roll, Runway Gen-4 Turbo"));
children.push(tbl([5060,2300,2000],
  ["Cost Item","USD","INR"],
  [
    ["Claude (full course generation)",{text:"~$0.25",align:CTR},{text:"~₹21",align:CTR}],
    ["Generated B-roll: 60 sec @ $0.05/sec",{text:"$3.00",align:CTR},{text:"₹255",align:CTR}],
    ["edge-tts narration (all 15 min)",{text:"$0.00",align:CTR,color:GREEN},{text:"₹0",align:CTR,color:GREEN}],
    ["Whiteboard, Iconify, Playwright, FFmpeg",{text:"$0.00",align:CTR,color:GREEN},{text:"₹0",align:CTR,color:GREEN}],
    [{text:"TOTAL per 15-minute course",bold:true,fill:LIGHT},{text:"~$3.25",align:CTR,bold:true,fill:LIGHT},{text:"≈ ₹276",align:CTR,bold:true,fill:LIGHT}],
  ]));

// 5 Honest caveats
children.push(h1("5. Honest Caveats (Read Before Budgeting)"));
children.push(b("Regeneration cost: AI clips often need 2–3 attempts to get a usable result. Runway and Kling do NOT charge for failed/errored tasks, but a clip that succeeds yet looks wrong still costs. Budget roughly 1.5×–2× the figures above for prompt iteration during early production.",true));
children.push(b("Clip length caps: single clips are usually 5–10 seconds. Longer continuous scenes require stitching multiple clips, multiplying cost.",true));
children.push(b("“Free” tools — commercial licensing: edge-tts and some Iconify icon sets are free to use, but for a commercial product their licences should be reviewed. A licensed TTS (or a small paid voice plan) may be required for full commercial safety; this is a small recurring cost, not a per-video one.",true));
children.push(b("Prices change: AI-video pricing moves quickly. The rates here are current as of June 2026 and should be re-checked before committing budget.",true));
children.push(b("Exchange rate: figures use ₹85 = $1 and will shift with the prevailing rate.",true));

// 6 Recommendation
children.push(h1("6. Recommendation"));
children.push(b("Use Runway Gen-4 Turbo (₹4.25/sec) or Kling 3.0 (₹8.50/sec) as the workhorse for silent B-roll; overlay free edge-tts narration."));
children.push(b("Target ~60 seconds of generated B-roll per 15-minute course → roughly ₹276 (Runway) to ₹531 (Kling), plus a 1.5× buffer for regenerations during setup."));
children.push(b("Reserve Veo 3.1 Fast/Standard for premium client deliverables where maximum realism is required."));
children.push(b("Build a reusable clip library: once a clip (e.g. “seatbelt fastening”) is generated, reuse it across courses so its cost amortises toward zero."));
children.push(p("Net effect: a 15-minute course with real generated demonstration footage costs roughly ₹276–₹531, with the free whiteboard engine and free voiceover keeping everything except the chosen B-roll at near-zero.",{bold:true}));

// 7 Sources
children.push(h1("7. Sources"));
children.push(b("Runway API Pricing & Costs — docs.dev.runwayml.com/guides/pricing (Gen-4 Turbo 5 credits/sec, $0.01/credit)."));
children.push(b("Kling AI Developer Pricing — kling.ai/dev/pricing (Kling 3.0 ≈ $0.10/sec)."));
children.push(b("Google Veo 3.1 API pricing — Vertex AI / Gemini API (Veo 3.1 Fast $0.15/sec, Standard $0.40/sec, Lite $0.03–0.05/sec)."));
children.push(b("Claude Haiku 4.5 pricing — Anthropic (current): $1/M input, $5/M output, $0.10/M cached input."));
children.push(p("Exchange rate assumption: ₹85 = $1.00 USD.",{italics:true,color:GREY}));

const doc=new Document({
  creator:"AI-Powered LMS",title:"Generative Video Cost Analysis",
  styles:{default:{document:{run:{font:"Arial",size:22,color:"1F2937"}}},
    paragraphStyles:[
      {id:"Heading1",name:"Heading 1",basedOn:"Normal",next:"Normal",quickFormat:true,
        run:{size:30,bold:true,color:NAVY,font:"Arial"},
        paragraph:{spacing:{before:320,after:160},outlineLevel:0,border:{bottom:{style:BorderStyle.SINGLE,size:6,color:BLUE,space:4}}}},
      {id:"Heading2",name:"Heading 2",basedOn:"Normal",next:"Normal",quickFormat:true,
        run:{size:25,bold:true,color:BLUE,font:"Arial"},
        paragraph:{spacing:{before:220,after:100},outlineLevel:1}},
    ]},
  numbering:{config:[{reference:"bullets",levels:[{level:0,format:LevelFormat.BULLET,text:"•",alignment:AlignmentType.LEFT,style:{paragraph:{indent:{left:540,hanging:280}}}}]}]},
  sections:[{
    properties:{page:{size:{width:12240,height:15840},margin:{top:1440,right:1440,bottom:1440,left:1440}}},
    footers:{default:new Footer({children:[new Paragraph({alignment:CTR,children:[
      new TextRun({text:"AI-Powered LMS  —  Generative Video Cost Analysis  —  Page ",size:16,color:GREY}),
      new TextRun({children:[PageNumber.CURRENT],size:16,color:GREY}),
    ]})]})},
    children,
  }],
});
Packer.toBuffer(doc).then(buf=>{fs.writeFileSync("Generative_Video_Cost_Analysis.docx",buf);console.log("WROTE Generative_Video_Cost_Analysis.docx");});
