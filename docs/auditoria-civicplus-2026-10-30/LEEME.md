# Auditoría CivicPlus y arquitectura ConDi

Entrega del 30 de octubre de 2026 · Consultora Diagonales.

Abrí informe-condi-civicplus.html para leer ambos documentos con navegación y diagrama. Funciona localmente, sin instalar paquetes ni iniciar un servidor. El contenido, logos, captura y diagrama están integrados. Los enlaces de descarga a PDF y anexos requieren conservar esta carpeta descomprimida.

## Contenido

- pdf/auditoria-condi-civicplus.pdf: auditoría funcional y técnica, 9 hallazgos y prioridades; 8 páginas.
- pdf/arquitectura-condi-crm.pdf: arquitectura propuesta, datos, comandos, SLA, permisos y migración; 8 páginas.
- auditoria.md y arquitectura.md: versiones editables de los documentos.
- inspeccion-condi.md: evidencia de código con rutas y líneas de la copia local.
- fuentes-civicplus.md: registro de 15 fuentes oficiales y límites de verificación.
- arquitectura.svg y arquitectura.mmd: diagrama vectorial y fuente Mermaid editable.
- backlog.csv: 12 iniciativas, dependencias, esfuerzo orientativo y criterios de aceptación.
- evidencia/: captura de la página, observaciones DOM y vistas del informe.
- validacion.json y MANIFEST.sha256: controles realizados y hashes del paquete.

## Alcance

Se revisó la página pública y el código local de ConDi. El formulario para acceder a los videos no se envió. La descarga directa del HTML y JavaScript externos respondió HTTP 403; se inspeccionó el DOM y los recursos/fragmentos inline de la pestaña abierta. La arquitectura privada de CivicPlus no se presenta como conocida.

Las mejoras son una propuesta; no se modificó ni desplegó código de la aplicación. Los permisos señalados requieren confirmación contra reglas desplegadas y pruebas de emuladores antes de corregir. Los rangos de esfuerzo no son cotización ni compromiso de calendario.

La identidad Diagonales se aplicó al informe navegable. Los PDF se revisaron renderizando sus 16 páginas y comprobando tablas, fuentes y diagrama. La validación de documentos no equivale a una auditoría WCAG o una prueba funcional del CRM privado.
