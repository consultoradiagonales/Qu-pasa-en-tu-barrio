---
name: "sesgo-del-superviviente"
description: Detecta sesgo del superviviente y sesgos de evidencia ausente en encuestas, datos politicos, electorales, de marketing o de negocio. Usar siempre que el usuario pida analizar una encuesta, un dato de aprobacion, un ranking de clientes, una muestra, un estudio o cualquier conclusion basada en "los que respondieron/sobrevivieron/quedan activos", o pida auditar un analisis en busca de sesgos ocultos, puntos ciegos o informacion faltante. Tambien usar de forma proactiva antes de validar cualquier conclusion de una radiografia, encuesta diagonales o reporte comercial que se apoye en una muestra observada, aunque el usuario no mencione la palabra "sesgo".
---

# Sesgo del Superviviente

Casi todo analisis mira solo los datos que sobrevivieron para llegar
a la muestra (encuestados, clientes activos, empresas exitosas).
Nombre y origen vienen del caso de Abraham Wald con los bombarderos
de la Segunda Guerra Mundial: el detalle historico esta en
`references/origen-wald.md`, no hace falta leerlo para aplicar la
skill. La leccion operativa es simple: antes de confiar en una
conclusion, preguntar que falta en la muestra y por que falta.

## Cuando se activa

- El usuario pide analizar una encuesta, sondeo, ranking, dato de
  aprobacion/rechazo, estudio de mercado o cartera de clientes.
- El usuario pide auditar un informe, radiografia o presentacion en
  busca de sesgos, puntos ciegos o informacion faltante.
- Antes de dar por buena una conclusion de este tipo en cualquier otro
  flujo de trabajo (radiografia, encuesta diagonales, analisis
  comercial), aunque no se mencione la palabra "sesgo" explicitamente.

## Procedimiento (siempre en este orden)

1. **Que observamos.** Listar los casos que efectivamente estan en la
   muestra o en el dato presentado.
2. **Que no observamos.** Listar que casos, personas o entidades
   podrian haber quedado fuera.
3. **Por que no lo observamos.** Identificar el filtro o mecanismo que
   produjo la ausencia (abandono, no respuesta, desaparicion,
   liquidacion, exclusion de diseno).
4. **Como distorsiona la conclusion.** Explicar en una o dos frases
   cortas el efecto concreto sobre lo que se afirma.
5. **Que falta para corregirlo.** Que dato adicional permitiria probar
   o descartar la distorsion.
6. **Riesgo analitico: Bajo / Medio / Alto.** Un solo nivel, con una
   frase que justifique por que.
7. **Conclusion reformulada.** Reescribir la conclusion original
   incorporando la hipotesis de los casos no observados, sin inventar
   cifras que no existen.

Nunca te saltees un paso ni lo comprimas en el mismo parrafo que el
anterior: cada paso es su propio bloque corto. Si para algun paso no
hay informacion suficiente, decir "No lo se" o "No hay datos para
estimarlo" en lugar de completar con un supuesto no declarado.

## Reglas no negociables (vienen del estilo de quien usa esta skill)

- Separar siempre hechos de supuestos. Si el paso 7 depende de una
  suposicion, decirla primero, en una linea aparte.
- Nunca inventar estadisticas, porcentajes, fuentes o citas. El
  "RIESGO DE DISTORSION: 82%" es un ejemplo de formato, no una cifra a
  reproducir: solo se pone un porcentaje si viene de un dato real
  provisto en la conversacion.
- Si no se sabe algo, decir "No lo se" en vez de adivinar.
- Parrafos cortos, de 2 a 4 lineas. Nunca un bloque largo.

## Modulos de aplicacion

El procedimiento de 7 pasos es el mismo siempre. Lo que cambia segun
el dominio son las preguntas tipicas de "que no observamos" y los
ejemplos de filtro. Ver `references/modulos.md` para:

- Modulo Estadistico (sesgo de seleccion, abandono, respuesta,
  publicacion, supervivencia empresarial)
- Modulo Politico-Electoral (encuestas de gestion, participacion
  territorial, entidades civiles activas vs. desaparecidas)
- Modulo Marketing/Negocio (clientes activos vs. exclientes, canales,
  correlaciones espurias)

Leer ese archivo antes de aplicar la skill a un caso de alguno de esos
tres dominios, porque trae las preguntas automaticas especificas que
conviene usar en el paso 2.

## Formato de salida

Usar siempre esta estructura de encabezados cortos (no fusionar pasos):

```
CASOS OBSERVADOS
[2-4 lineas]

CASOS AUSENTES PROBABLES
[2-4 lineas]

FILTRO QUE EXPLICA LA AUSENCIA
[1-3 lineas]

COMO DISTORSIONA LA CONCLUSION
[1-3 lineas]

QUE DATO FALTA PARA CORREGIRLO
[1-3 lineas]

RIESGO ANALITICO: Bajo / Medio / Alto
[1 linea de justificacion]

CONCLUSION REFORMULADA
[1-3 lineas]
```

Si el usuario solo pide "aplicar sesgo del superviviente a X" sin mas
contexto, pedir el dato minimo imprescindible (la conclusion o cifra
original y de donde sale la muestra) antes de completar el formato —
no rellenar con hipoteticos genericos.

## Origen del metodo

Ver `references/origen-wald.md` solo si el usuario pide el contexto
historico completo o la formulacion bayesiana del caso Wald.
