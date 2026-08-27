# Technical Work

Add a curated `Technical Work` section after Books and before Interviews.

## Presentation

Use the existing visual language:

`Title · co-authors · venue · year  [Paper] [Preprint] [Code]`

Call the section `Technical Work` rather than `Papers` so it can eventually
include software and other technical artifacts without changing scope.

## Initial works

- [ ] *Quantum theory, the Church–Turing principle and the universal quantum computer* · 1985 · [Official PDF](https://www.daviddeutsch.org.uk/wp-content/deutsch85.pdf)
- [ ] *Quantum computational networks* · 1989 · [Royal Society](https://doi.org/10.1098/rspa.1989.0099)
- [ ] *Quantum Theory of Probability and Decisions* · 1999 · [arXiv](https://arxiv.org/abs/quant-ph/9906015)
- [ ] *Constructor Theory* · 2013 · [arXiv](https://arxiv.org/abs/1210.7439)
- [ ] *Constructor Theory of Information* · with Chiara Marletto · 2015 · [arXiv](https://arxiv.org/abs/1405.5563)
- [ ] *The Logic of Experimental Tests, Particularly of Everettian Quantum Theory* · 2016 · [Constructor Theory](https://www.constructortheory.org/portfolio/logic-experimental-tests/)
- [ ] *Constructor Theory of Time* · with Chiara Marletto · 2025 · [Constructor Theory](https://www.constructortheory.org/portfolio/constructor-theory-of-time/)

## Data model

```yaml
technical_work:
  - title:
    authors:
    publication:
    published_date:
    url:
    preprint_url:
    code_url:
```

## Scope

Include work authored or co-authored by David Deutsch. Do not automatically
include every paper developed within the broader Constructor Theory programme.

The section should remain curated rather than becoming a complete bibliography.
Use the [Constructor Theory research index](https://www.constructortheory.org/research/)
as a discovery source, then verify authorship and canonical links individually.
