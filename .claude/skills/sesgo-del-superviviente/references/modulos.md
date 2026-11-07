# Modulos de aplicacion

Cada modulo da preguntas tipicas para el paso 2 ("que no observamos")
del procedimiento principal. Son puntos de partida, no una lista
cerrada: siempre pensar si hay algo propio del caso que no esta aqui.

## Modulo Estadistico

Sesgos frecuentes a buscar:
- Sesgo de seleccion (quien entro a la muestra).
- Sesgo de abandono (quien dejo de participar antes de terminar).
- Sesgo de respuesta (quien respondio vs. quien ignoro la consulta).
- Sesgo de publicacion (que estudios con resultado negativo no se
  publican o no se citan).
- Sesgo de supervivencia empresarial (solo se analizan empresas o
  fondos que siguen existiendo hoy).

Preguntas automaticas:
- ¿Quienes respondieron?
- ¿Quienes no respondieron, y por que no?
- ¿Hay sujetos morosos, desvinculados o insatisfechos que quedaron
  fuera de la muestra por el propio diseño de la consulta?

Ejemplo de uso (formato, no dato real):
Afirmacion: "85% de los contribuyentes considera adecuada la tasa
municipal."
Pregunta: ¿quienes no respondieron la encuesta? ¿hay contribuyentes
morosos o desvinculados que no participaron?
Riesgo tipico en este patron: ALTO, porque la muestra puede estar
representando solo a ciudadanos activos y conformes.

## Modulo Politico-Electoral

Este es el modulo de mayor valor para campaña y gestion, porque la
ausencia de un sector entero (un barrio, una franja etaria, un ex
votante) suele pesar mas que el error de muestreo comun.

Preguntas automaticas:
- ¿Quien aparece en los datos (seguidores, panelistas, entidades
  consultadas)?
- ¿Quien no aparece, y por que no aparece?
- ¿Que barrios o secciones tienen participacion nula o muy baja?
- ¿Que grupos dejaron de responder encuestas en comparacion con
  mediciones anteriores?
- ¿Que organizaciones o entidades desaparecieron del radar
  institucional (clubes, cooperadoras, camaras, centros de jubilados)
  y por eso no estan en el relevamiento?

Ejemplo de uso (formato, no dato real):
Afirmacion: "70% aprueba la gestion."
Base tipica: seguidores activos en redes o panel fidelizado.
Ausentes tipicos: ex votantes decepcionados, electores independientes
que no siguen la cuenta oficial, jovenes desmovilizados que no
contestan encuestas telefonicas.
Riesgo tipico: la aprobacion observada puede estar sobreestimada
porque la base estructuralmente excluye al descontento silencioso.

Caso de entidades civiles (clubes, cooperadoras, sociedades rurales,
camaras empresarias, centros de jubilados): si el relevamiento solo
lista las entidades actualmente activas, falta todo registro de las
que dejaron de funcionar — y esas bajas institucionales suelen ser en
si mismas un dato politico relevante que el relevamiento esta
omitiendo por diseño.

## Modulo Marketing / Negocio

La mayoria de los dashboards miran clientes actuales, clientes
recurrentes, seguidores activos y leads convertidos. Rara vez miran
exclientes, leads perdidos, gente que abandono o seguidores que
dejaron de interactuar.

Preguntas automaticas:
- ¿Que canal, producto o mensaje usaban los clientes que abandonaron?
- ¿El analisis mira solo a quienes permanecieron?
- ¿Hay una correlacion que podria ser espuria porque el grupo de
  comparacion (los que se fueron) nunca entro al dataset?

Ejemplo de uso (formato, no dato real):
Afirmacion: "Los clientes mas rentables usan WhatsApp."
Pregunta: ¿que canal usaban los clientes que abandonaron? ¿se
compara contra algun grupo que ya no esta?
Riesgo tipico: posible correlacion espurea si el canal "ganador" es
simplemente el que usan los clientes que, por otras razones, iban a
quedarse de todos modos.

## Nota sobre el modulo ampliado (4 motores)

El material original tambien describe una version ampliada con
cuatro motores simultaneos (Survivorship Bias, Selection Bias, Silent
Stakeholder Detection, Missing Data Risk) bajo el nombre "Strategic
Blind Spot Analyzer". Esta skill cubre el nucleo (Survivorship +
Selection, que son los que el procedimiento de 7 pasos ya ejercita).
Si en el futuro se necesita Silent Stakeholder Detection y Missing
Data Risk como motores separados y explicitos, conviene crearlos como
skills propias que llamen a esta como base, en vez de inflar esta
skill con mas pasos.
