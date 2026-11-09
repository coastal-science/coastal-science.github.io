---
title: "{{ replace .Name "-" " " | title }}"
date: {{ .Date }}
workshop: ""  # required: same slug as data/workshop/<slug>/info.yaml
---

# Workshop Schedule

{{< workshop >}}
