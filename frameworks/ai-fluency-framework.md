---
title: "AI Fluency Framework"
type: framework
tags: [framework, ai-fluency, delegation, description, discernment, diligence, methodology]
source: "Dakan & Feller — Framework for AI Fluency (CC BY-NC-ND 4.0)"
related:
  - "[[AI Governance Policy]]"
---

# AI Fluency Framework

> **AI Fluency** — the ability to work with AI effectively, efficiently, ethically, and safely.

This is a practitioner reference for the 4 D's framework, distilled from Anthropic's AI Fluency course. It provides a shared vocabulary for building AI systems and workflows — the same language Anthropic teaches in their training programs.

---

## Three Modes of AI Interaction

Before the 4 D's, understand *how* humans and AI can work together. Every task falls into one of these modes:

| Mode | What It Means | When to Use It |
|------|---------------|----------------|
| **Automation** | AI executes a specific task based on your instructions | Repetitive, data-heavy, or time-consuming work — emails, summaries, formatting, basic code |
| **Augmentation** | You and AI collaborate as thinking partners, iterating together | Creative work, complex problem-solving, research, writing, architecture decisions |
| **Agency** | You configure AI to independently handle tasks for others | Chatbots, tutors, interactive tools, AI-powered features in products you build |

**Key insight:** Choosing the right mode is itself a Delegation decision. Most people default to Automation when Augmentation would produce far better results.

---

## The 4 D's

### 1. Delegation

*Deciding what work belongs to you, to AI, or to both of you together.*

Delegation is the starting point. Before you write a single prompt, you need to know what you're trying to accomplish and whether AI is the right tool.

**Problem Awareness** — What are you actually trying to do?
- Define the goal before involving AI
- Break the work down: what requires human judgment, creativity, or domain expertise? What's mechanical?
- Consider the stakes — high-stakes decisions need more human oversight

**Platform Awareness** — What can this AI actually do?
- Understand the strengths and limitations of the tool you're using
- Know about context windows, knowledge cutoffs, and hallucination risks
- Match the tool to the task (don't use a chatbot for image generation)

**Task Delegation** — Who does what?
- Assign work based on actual strengths: AI is fast at synthesis, drafting, and pattern recognition; humans are better at judgment, nuance, and stakeholder awareness
- Consider the interaction mode (Automation vs. Augmentation vs. Agency)
- Build in checkpoints — don't hand off an entire project without review gates

---

### 2. Description

*Communicating what you need in a way that produces useful results.*

This is where prompting lives, but it's broader than just writing prompts. It's about translating your vision into something AI can act on.

**Product Description** — What should the output look like?
- Be specific about format, length, tone, audience, and style
- Show examples of what "good" looks like (few-shot prompting)
- Define constraints up front rather than correcting after the fact

**Process Description** — How should AI approach the work?
- Break complex tasks into steps rather than one massive prompt
- Ask AI to think through its reasoning before giving a final answer (chain-of-thought)
- Use iterative conversation — first draft, feedback, refinement

**Performance Description** — How should AI behave during the collaboration?
- Define the role: expert advisor, brainstorming partner, editor, devil's advocate
- Set the communication style: concise or detailed, challenging or supportive
- Specify what AI should do when uncertain (ask vs. assume)

#### 6 Prompting Techniques (Quick Reference)

1. **Provide context** — Be specific about scope, domain, audience, constraints
2. **Show examples** — Give 1-3 examples of the quality and format you want (few-shot learning)
3. **Specify output constraints** — Format, length, structure, tone
4. **Break complex tasks into steps** — One clear instruction per prompt when needed
5. **Ask it to think first** — "Walk through your reasoning before answering"
6. **Define the AI's role** — Character, expertise level, communication style

---

### 3. Discernment

*Critically evaluating what AI gives you — never accepting output at face value.*

This is the quality control competency. AI can be confidently wrong (hallucination), subtly biased, or technically correct but contextually inappropriate.

**Product Discernment** — Is this output actually good?
- Check for accuracy, especially factual claims, numbers, and citations
- Evaluate appropriateness for your audience and context
- Assess coherence — does it hold together logically?
- Judge relevance — does it actually address what you asked?

**Process Discernment** — Is the reasoning sound?
- Look for logical errors or gaps in the AI's thinking
- Watch for the AI agreeing too readily or changing position without justification
- Notice when it's pattern-matching rather than actually reasoning about your specific situation

**Performance Discernment** — Is the collaboration working?
- Is the AI's communication style helping or hindering?
- Are you getting diminishing returns from continued iteration?
- Would a different approach (new prompt, different mode, human-only) be more effective?

**The Discernment Loop:** Description and Discernment form a continuous cycle — you describe, evaluate the result, refine your description, evaluate again. This iterative loop is where quality actually happens.

---

### 4. Diligence

*Taking full responsibility for everything you produce with AI.*

When you put your name on AI-assisted work, you're vouching for it. Diligence is about doing that responsibly.

**Creation Diligence** — Are you using AI thoughtfully?
- Choose tools and approaches that match your ethical standards
- Be aware of how AI systems are trained and what biases they may carry
- Consider the impact on people affected by your work
- Don't use AI to do things you wouldn't do yourself

**Transparency Diligence** — Are you honest about AI's role?
- Different contexts have different disclosure expectations
- Professional, academic, creative, and personal work each have norms
- When in doubt, disclose — transparency builds trust
- See [[AI Governance Policy]] for specific disclosure templates and criteria

**Deployment Diligence** — Have you verified the final product?
- Fact-check claims, especially anything AI generated with high confidence
- Test functionality before shipping
- Validate that the output serves its intended audience
- You are accountable for the result, regardless of how it was produced

---

## Applying This in Your Work

The 4 D's map naturally to different professional roles:

**As a developer:**
- **Delegation** = deciding what to code yourself vs. what AI generates
- **Description** = writing effective prompts and system instructions
- **Discernment** = code review and testing of AI-generated code
- **Diligence** = ensuring quality, security, and maintainability

**As a writer:**
- **Delegation** = choosing which parts of the writing process benefit from AI
- **Description** = guiding AI on voice, tone, structure, and audience
- **Discernment** = editing for accuracy, originality, and authenticity
- **Diligence** = fact-checking and proper attribution

**As a designer:**
- **Delegation** = identifying where AI accelerates the design process
- **Description** = communicating visual and experiential intent to AI tools
- **Discernment** = evaluating AI outputs against design principles and user needs
- **Diligence** = ensuring accessibility, inclusivity, and ethical representation

**As a consultant:**
- **Delegation** = scoping what AI should and shouldn't do in client workflows
- **Description** = prompt engineering and system design
- **Discernment** = quality assurance and validation checkpoints
- **Diligence** = governance, disclosure practices, and accountability structures

The framework is platform-agnostic and won't break when tools change. Focus on the *thinking* behind effective AI use, not just which buttons to click.

---

## Key Vocabulary

| Term | What It Means |
|------|---------------|
| **Generative AI** | AI that creates new content (text, images, code) rather than classifying existing data |
| **LLM** | Large Language Model — the type of AI behind tools like Claude, ChatGPT |
| **Context window** | Maximum amount of information the AI can process at once |
| **Hallucination** | When AI generates confident but incorrect information |
| **Knowledge cutoff** | The date after which the AI has no training data |
| **Chain-of-thought** | Prompting technique: ask AI to show its reasoning step by step |
| **Few-shot learning** | Teaching AI what you want by providing examples in your prompt |
| **RAG** | Retrieval Augmented Generation — connecting AI to external knowledge sources for accuracy |
| **Temperature** | Controls randomness/creativity in AI outputs (lower = more predictable) |
| **Fine-tuning** | Customizing an AI model for specific tasks using additional training data |

---

## Source & Attribution

This framework was developed by **Prof. Rick Dakan** (Ringling College of Art and Design) and **Prof. Joseph Feller** (Cork University Business School). It is published under CC BY-NC-ND 4.0.

Course materials available through **Anthropic's AI Fluency program** (Skilljar).

This document was created with AI assistance (Claude). All content was reviewed, contextualized, and adapted for practitioner use.
