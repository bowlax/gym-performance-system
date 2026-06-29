# Coach / Owner Discovery Guide

**Purpose:** Capture how the owner actually coaches and runs the gym, so phase 2 can be designed around real working practice rather than assumptions.

**Format:** Designed to be sent via WhatsApp. He answers each question as voice messages at his own pace.

**The golden rule for you (not him):** You're capturing how he *works*, not what he thinks the app *should do*. If he starts designing features, that's fine -- but note the underlying need beneath the suggested feature. When he says "it should flag people who drop off", the real use case is "I need to know when someone's stopped showing up". Capture the need, not the feature.

---

## The intro message to send

> Hey -- as I build out the next version of the app, the most useful thing I can do is properly understand how you actually coach and run things day to day. So rather than me guessing what would help, I'd love you to talk me through a few things.
>
> Don't overthink it -- just answer these as voice notes whenever you get a chance, as long or short as you like, and feel free to ramble. The more you just talk through how you actually do things, the better. There are no wrong answers and you don't need to think about the app at all -- just tell me how you work.
>
> I'll send them one at a time so it's not overwhelming.

---

## The questions

Send these one at a time, ideally letting him answer each before sending the next. Each is designed to invite a story rather than a short answer.

### 1. The normal week
> Talk me through how you set up a normal week at the gym. What are you doing each week and each day -- not the big picture stuff, just the ordinary running of it?

*(Draws out the rhythm of how he works and where the app might fit.)*

### 2. Spotting who's doing well
> When you look around the gym, how do you know who's doing well and who's not? What tells you someone's progressing nicely versus someone who's stuck or struggling?

*(This is the heart of the owner's strategic use case -- how he currently reads performance.)*

### 3. Spotting who's slipping
> Tell me about a time someone started dropping off -- missing sessions, losing motivation, going backwards. How did you notice, and what did you do about it?

*(Real story draws out the flag/insight use cases without him having to imagine features.)*

### 4. How goals actually work
> Walk me through how goals work with your members. How do you set them, how do you keep track, and what happens when someone hits one or misses one?

*(Goal Management is a major phase 2 component -- this captures how it really works.)*

### 5. Sessions over time
> You mentioned before that you'd want to see how sessions are set up over time. Tell me more about that -- what would you actually be looking for, and what would you do with it?

*(Draws out the owner aggregation and programme-effectiveness use case.)*

### 6. The things you can't see
> Is there anything you wish you could see or know about your members or the gym that you just can't easily get at right now? Even if it feels impossible.

*(Surfaces latent needs -- often the most valuable use cases come from here.)*

### 7. The other coaches
> The other two coaches -- how do they work with member information? Do they need to see the same things you do, or different things? And is there anything you'd want to see that they shouldn't, or the other way round?

*(Clarifies the coach vs owner access distinction we have in the architecture.)*

### 8. If it just worked
> Last one. Imagine the app just quietly did its job in the background and gave you exactly what you needed. What would that actually change for you or the gym? What would be different?

*(Captures the real value he's hoping for -- useful for prioritising what matters most.)*

---

## After he responds -- what to do with it

For each voice message, listen for:

- **Verbs** -- what he *does* (notices, checks, sets, reviews, chases, adjusts). These become use cases.
- **Pain** -- where something is hard, slow, or impossible now. These are the high-value opportunities.
- **Frequency** -- how often something happens. Daily things matter more than yearly ones.
- **Solutions in disguise** -- when he describes a feature, note the need beneath it.

Bring the transcribed or summarised responses back to Claude, and we'll turn them into:
- Coach surface use cases
- Owner surface use cases
- Connected member Group 2 use cases (goals, commentary, flags)
- Any new volatilities that surface

That completes the parked use case capture and unblocks the rest of phase 2 design.

---

## A note on scope discipline

He may describe things that are genuinely phase 3 or beyond -- complex analytics, integrations, automation. That's fine and useful to capture, but don't let the conversation expand phase 2 scope. Note ambitious ideas in the backlog and keep phase 2 focused on the confirmed components: Coach Surface, Owner Surface, Goal Management, Insight Engine, Aggregation Service, and the sync foundation.
