# Why This Platform Exists

Any developer can open an AWS account and deploy a container. So why put a platform — a stack of control
planes and policies — between them and the cloud?

Because getting one service to production isn't the hard part. Keeping fifty of them secure, observable,
compliant, and consistent is — and almost none of that work has anything to do with the product a team is
trying to ship.

Look at what stands between a team's code and its first real request: networking and a Kubernetes cluster, an
image registry with signing and provenance, a delivery pipeline with canary rollouts and rollback,
least-privilege IAM, secrets management, admission and network policy, metrics and logs and traces, SLOs,
on-call — then all of it patched and audited, indefinitely. None of it ships a feature. Werner Vogels has a
name for this kind of work: *undifferentiated heavy lifting* — necessary, and completely beside the point of
your product.

Now multiply it. When every team builds that stack itself, you don't get one of each; you get fifty, each
subtly different, each its own thing to secure, debug, and understand. Nobody knows more than a couple of
them. Spotify called the result *rumour-driven development*: the only way to learn how something worked was to
find the person who did it last.

## The idea

A platform's job is to take that work off the teams and make the secure, compliant, production-grade path the
easiest one to walk.

Not the only path — that's a cage. Not a path you still have to be an expert to walk — that just moves the
burden around. The easiest one, so that signing an image or scoping a role takes less effort than skipping it.
When the paved road is also the path of least resistance, security and compliance stop being things people
remember to do and start being things they get for free.

For a developer, the job then shrinks to three steps: write the service, declare an environment, open a pull
request. Everything downstream — provisioning, policy checks, the progressive rollout, the observability —
happens without them. The whole promise rests on one equivalence holding: "deploy to a secure, multi-account,
policy-governed, progressively-delivered, fully-observed production environment" and "merge a pull request"
have to mean the same thing.

## What it buys

- **Speed that doesn't cost safety.** A change ships in minutes, and it arrives signed, scanned,
  policy-checked, and canaried — because those aren't extra steps bolted on, they're the road itself.
- **One shape.** One way to deploy, one security posture, one observability stack. When every service looks
  the same, anyone who has learned the shape can operate any of them.
- **Less to carry.** A developer reasons about their service, not about how cluster admission works.
- **Governance that holds at scale.** Security, cost, and compliance are enforced once, for everyone, at the
  door — not re-argued in fifty separate code reviews.

A handful of platform engineers make a large number of product teams faster. That leverage is the whole
economic argument.

## A product, not a mandate

None of it works if teams are pushed onto the platform. Its users are other engineers, and like any product it
wins by being genuinely the easiest way to work — not by decree. If the road isn't actually paved (documented,
self-service, pleasant to use), people route around it and you've built a toll booth nobody pays. The CNCF's
platforms working group and Evan Bottcher land on the same point: a platform is a product, and knowledge and
support — docs, examples, a site like this one — are part of it, not a nicety.

## The bets this one makes

Everything above holds for any internal platform. This one places specific bets on how to keep the "merge a
PR" promise without giving up safety:

- **Declarative, driven by Git.** You describe the state you want; control planes make it real and hold it
  there. Nothing imperative to babysit, and it repairs itself when reality drifts.
- **Self-service inside guardrails.** A team gets a whole environment from a short claim, but what a claim is
  allowed to ask for is bounded by policy. That's the only kind of self-service that survives scale.
- **Multi-tenant from the start.** Many teams share the platform with real isolation between them — a platform
  that only works for one tenant hasn't proven anything.
- **Compliance as a dimension, not a bolt-on.** Tiers and guardrails are built in, and the docs stay honest
  about where that's still thin.
- **Room for the next kind of workload.** The same governed path that carries services is starting to carry
  autonomous agents; the model was built to extend, not just to run what exists today.

Put together, that's a single wager: the developer experience of a hosted platform with the governance of a
regulated enterprise. Most platforms pick one end. The bet here is that a control-plane architecture lets you
refuse the tradeoff.

## One honest thing

This is a reference implementation. It doesn't serve a real company's developers — it exists to show, end to
end, how a governed internal platform can be built well, in a form other engineers can read and take apart.
That's why it's built as if it ran at real scale: the point is the pattern, not the traffic. It also runs its
own services on the same rails it hands everyone else — the fastest way to learn whether a road is any good is
to be made to drive on it.
