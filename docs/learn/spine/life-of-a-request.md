# The Life of a Request

Your fix is live. A customer opens their browser and hits
`https://shop-acme-dev.preprod.aws.refplat.org`, and a few dozen milliseconds later they have a page.

What happened in those milliseconds between their browser and your pod — and what *didn't*? The second
question is the more revealing one. It's the cleanest way to see the most important boundary in the
platform.

[The Life of a Deployment](life-of-a-deployment.md) followed one `git push` through the *control* plane,
the machinery that makes things exist. This follows one user request through the *data* plane, the
machinery that serves them.

## This is the data plane, and it barely touches the control plane

Follow the request all the way through: it never talks to ArgoCD, Crossplane, or Kyverno. None of the
control planes that *built* this environment are in the request's path. The request flows through the
running result of all that machinery, not the machinery itself.

That's the **control plane / data plane** split from [How the Platform Fits](how-the-platform-fits.md),
and a live request is the clearest way to feel it. The control plane makes things exist and keeps them
healthy. The data plane serves actual users. A deployment is a control-plane event — ArgoCD, Crossplane,
Kyverno, Rollouts deciding what should run. A request is a data-plane event — DNS, the gateway, Cilium,
your pod carrying real traffic. Different components, different failure consequences.

A metaphor to hold the whole journey: the deployment built and staffed an office building — poured the
foundation, wired it, hired the staff, all control plane. A request is a visitor walking in to be served,
the data plane. The builders and facilities managers aren't in the room when the visitor is helped; the
building they made does the work. Where it breaks: unlike a real building, this one is continuously
re-inspected and self-healed *while* visitors are served — the control plane never fully leaves, it just
isn't in the request path.

## Watch it happen — one request, edge to pod and back

Follow one HTTP GET to `shop`'s `web` service, browser to response. The whole path at a glance, then each
hop:

![One HTTP request, edge to pod and back: browser → Cloudflare (NS delegation) → Route53 → the internet-facing NLB → the Cilium Gateway (Envoy, TLS terminated) → HTTPRoute match → the pod in its namespace, and the response back out. An observability envelope wraps the whole path (ambient, not a step); step 4 carries the one control-plane coupling (the Rollout-weighted route); and a strip shows what's *not* in the path — the control plane the request never touches.](images/life-of-a-request.svg)

**1 · The browser — the request begins.** A customer clicks, and their browser fires an `HTTP GET` for
`shop`'s `web` service at `shop-acme-dev.preprod.aws.refplat.org`. Everything below is the platform
answering that single request.

**2 · DNS — finding the door.** First that hostname has to become an IP.
That name exists because external-dns published a Route53 record for it when the `HTTPRoute` was
created, pointing at the cluster's shared gateway load balancer — one gateway, with a wildcard
`*.<domain>` listener, fronts every environment's routes. This is looking up the building's address before
you drive there. The browser now has an IP: the gateway.

**3 · NLB → Envoy — the edge, and TLS opened.** The request lands on the gateway's network load balancer,
which fronts Cilium's built-in Envoy proxy — the single ingress point for external traffic into the cluster.
The front entrance of the building. (On preprod, tenant apps are internet-facing for external testing and
demos; platform and internal services sit behind a Tailscale-only internal gateway instead — same
machinery, a different door.) Envoy terminates TLS there, using a certificate cert-manager obtained and
auto-renews; from here in, the request travels the cluster's private network — the courier's sealed
envelope opened at the front desk by someone authorized to read it. One detail to hold: Envoy acts under a
special reserved Cilium identity, `ingress`, which matters two steps from now.

**4 · The HTTPRoute — the receptionist routes you.** Here the [Gateway API](https://gateway-api.sigs.k8s.io/)
does its job. An HTTPRoute matches the request's Host (`shop-acme-dev…`) and path and picks the backend:
`shop`'s `web` Service. The receptionist reads your appointment and sends you to the right floor.

This is the one place the request touches the deployment story. If `shop` is mid-rollout, that HTTPRoute is
*weighted* — [Argo Rollouts](https://argo-rollouts.readthedocs.io/en/stable/), through its Gateway-API
traffic-router plugin, has edited the route so that (say) 10% of requests go to the *canary* version and
90% to *stable*. So this very request is assigned to canary-or-stable by a weight the control plane set.
Reception waves some visitors into the newly-renovated wing and some into the original, deciding per
visitor. The [canary analysis](life-of-a-deployment.md) — the Rollout judging this slice's metrics to
decide whether the new version is healthy — is watching what happens to these exact requests.

The request never spoke to Argo Rollouts, yet a *deployment* decision steered it. Rollouts expressed that
decision by editing the HTTPRoute weights, a data-plane object, then stepped out of the request path.
The control plane changes the data plane's configuration and lets the request follow the weights it finds.

**5 · Network policy — the security checkpoint.** Before the traffic reaches a pod, Cilium checks its
network policy: is the source — Envoy's `ingress` identity — allowed to reach `shop-web`'s pods? The
environment's `CiliumNetworkPolicy` must explicitly permit `fromEntities: [ingress]`, or the packet is
dropped. A badge reader at the floor's entrance: even inside the building, you don't get in without the
right credential. This is a data-plane wall from [the security model](the-security-model.md) —
least-privilege connectivity, enforced on every packet.

**6 · Service to pod — the elevator dispatcher.** The Service is a `ClusterIP`, and Cilium — running
[kube-proxy replacement](https://docs.cilium.io/en/stable/overview/intro/) in eBPF (there is no
kube-proxy here) — load-balances the connection to one *healthy* pod of whichever `shop-web` Service
(stable or canary) the weighted `HTTPRoute` already picked in step 4, honoring the readiness gates. The
dispatcher sends you to an available, staffed floor, never a dark one.

**7 · The pod serves — the actual work.** Finally the request reaches your application code, and it does the
thing: renders the page. If it needs AWS along the way — read its S3 bucket, enqueue a job — it uses the
credentials it got from Pod Identity (short-lived, scoped, no static keys). If it needs *another
service* — say it calls a `checkout` API — that's an east-west hop, allowed or denied by Cilium network
policy between pods, encrypted on the wire (WireGuard) and, where a policy sets
`authentication.mode: required`, mutually authenticated so the two services cryptographically prove who
they are (SPIFFE identity via SPIRE). This is the live `acme-shop → acme-checkout` showcase —
[ADR-057](../../adrs/057-service-identity-and-east-west-zero-trust.md); fleet-wide enforcement is the
remaining step.

**Observed the whole time — the envelope around every step, not one of them.** The request is being watched without
anyone instrumenting it by hand. [OpenTelemetry](https://opentelemetry.io/docs/) / eBPF
auto-instrumentation records a trace of the request's path, RED metrics (rate, errors, duration)
tick up, and logs are captured. Security cameras and a visitor logbook that write themselves. This is the
same data feeding the SLO and — if `shop` is mid-rollout — the canary analysis deciding whether the new
version lives.

**8 · The response — back out the door.** The pod's response retraces the path: back through Cilium, back to
Envoy, back out the load balancer, back to the browser. Milliseconds after they clicked, the customer has
their page, with no idea any of the above happened. Which is exactly the goal.

## Why the two planes being separate is the whole point

Line up who was involved in each life and the platform's most important safety property falls out:

![The control plane and the data plane are separate. The control plane (ArgoCD · Crossplane · Kyverno · Rollouts · CI) makes things exist and keeps them healthy, triggered by a git change. The data plane (DNS · Envoy · Cilium · your pod · Pod Identity) serves real user traffic, triggered by a user's click. The emphasized payoff — if it's down: the control plane going dark means new changes can't be made, but traffic keeps flowing.](images/two-planes.svg)

That last row is the payoff — the **air-traffic-control** metaphor from
[How the Platform Fits](how-the-platform-fits.md) made literal: if the control plane goes dark, planes
already in the air keep flying. ArgoCD down? Existing requests still serve — you just can't *deploy*.
Crossplane down? Running environments still take traffic — you just can't *provision new ones*. The request
path depends on almost none of the control plane, by design, so the blast radius of a control-plane outage
is "can't change things," not "everything is down."

The one deliberate coupling — the HTTPRoute weight — is worth appreciating for how clean it is. The control
plane doesn't sit in the request path steering traffic packet by packet; it edits a piece of data-plane
config (the route weights) and lets the data plane carry it out. Configure, then step back — the same
instinct as everything else on the platform.

## Common mix-ups

- **"The gateway load-balances to my pods."** The gateway (Envoy) routes by Host/path to a *Service*;
  **Cilium's eBPF** does the actual pod-level load-balancing (there's no kube-proxy). Two different jobs.
- **"Argo Rollouts sits in the traffic path during a canary."** No — it *edits the HTTPRoute weight* and
  leaves. The data plane routes each request by the weight it finds; Rollouts just watches the metrics.
- **"A request goes through Kyverno."** Kyverno is *admission* — it gates resources being *created*, not
  requests being *served*. It's nowhere near the data path.
- **"If ArgoCD is down, the site is down."** The site keeps serving; you just can't deploy changes.
  Control-plane availability isn't data-plane availability.

## Go deeper

- The other half — the control plane in motion: [The Life of a Deployment](life-of-a-deployment.md).
- The standing structure both move through: [How the Platform Fits](how-the-platform-fits.md) (see the
  control-plane / data-plane boundary) · [The Security Model](the-security-model.md) (the data-plane walls:
  network policy, mTLS gap).
- The planes as full modules *(coming — [inventory](../_inventory.md))*: Ingress & traffic (Gateway API,
  cert-manager), the cluster & CNI (Cilium), Progressive delivery (Rollouts), Observability.
- The substrate: [Gateway API](https://gateway-api.sigs.k8s.io/) · [Cilium](https://docs.cilium.io/en/stable/overview/intro/) ·
  [cert-manager](https://cert-manager.io/docs/) · [Argo Rollouts](https://argo-rollouts.readthedocs.io/en/stable/) ·
  [OpenTelemetry](https://opentelemetry.io/docs/).
