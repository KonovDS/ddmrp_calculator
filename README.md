# DDMRP Calculator for CML JCB

> **Note:** This is the public, open-source portion of the project. The private repository contains proprietary client data and internal configuration that cannot be shared.

A web application implementing a [Demand-Driven MRP](https://ddmrp.com/) restock strategy for an authorized heavy machinery distributor and service provider.

Built in Julia using [Genie.jl](https://genieframework.com/).

## What it does

- **Zones Calculator** — uploads historical sales data and per-SKU parameters, computes DDMRP buffer zones (red / yellow / green), and exports results as `.xlsx`
- **Order Generator** — given current stock levels, determines which SKUs need replenishment and generates an order file
- **Simulation** — replays historical demand against computed buffer zones and renders interactive per-SKU charts

## Documents

- [`stochastic_intro.pdf`](stochastic_intro.pdf) — background on the stochastic demand model used for zone sizing
- [`cml_presentation.pdf`](cml_presentation.pdf) — project presentation to management

## Screenshots

> The application shown below is a final, unpublished version of the tool — its source code is not part of this repository.

![Zones Calculator upload screen](screenshots/1.png)

![Zones Calculator demand visualization](screenshots/2.png) 

![Simulation visualization](screenshots/3.png) 