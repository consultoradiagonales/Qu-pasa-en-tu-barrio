// Generado el 2026-11-06 cruzando Georef (departamentos de la provincia 06)
// con MOTOR METEOROLOGICO/argwx/app/data/municipios_pba.json.
// Solo sirve para elegir datos meteorológicos: no une permisos ni registros.

/// Código Georef de municipio (seis dígitos) → identificador del partido en ARGWX.
const Map<String, String> argwxIdByGeorefCode = {
  '060007': 'adolfo-alsina', // Adolfo Alsina
  '060014': 'adolfo-gonzales-chaves', // Adolfo Gonzales Chaves
  '060021': 'alberti', // Alberti
  '060028': 'almirante-brown', // Almirante Brown
  '060035': 'avellaneda', // Avellaneda
  '060042': 'ayacucho', // Ayacucho
  '060049': 'azul', // Azul
  '060056': 'bahia-blanca', // Bahía Blanca
  '060063': 'balcarce', // Balcarce
  '060070': 'baradero', // Baradero
  '060077': 'arrecifes', // Arrecifes
  '060084': 'benito-juarez', // Benito Juárez
  '060091': 'berazategui', // Berazategui
  '060098': 'berisso', // Berisso
  '060105': 'bolivar', // Bolívar
  '060112': 'bragado', // Bragado
  '060119': 'brandsen', // Brandsen
  '060126': 'campana', // Campana
  '060134': 'canuelas', // Cañuelas
  '060140': 'capitan-sarmiento', // Capitán Sarmiento
  '060147': 'carlos-casares', // Carlos Casares
  '060154': 'carlos-tejedor', // Carlos Tejedor
  '060161': 'carmen-de-areco', // Carmen de Areco
  '060168': 'castelli', // Castelli
  '060175': 'colon', // Colón
  '060182': 'coronel-rosales', // Coronel Rosales
  '060189': 'coronel-dorrego', // Coronel Dorrego
  '060196': 'coronel-pringles', // Coronel Pringles
  '060203': 'coronel-suarez', // Coronel Suárez
  '060210': 'chacabuco', // Chacabuco
  '060218': 'chascomus', // Chascomús
  '060224': 'chivilcoy', // Chivilcoy
  '060231': 'daireaux', // Daireaux
  '060238': 'dolores', // Dolores
  '060245': 'ensenada', // Ensenada
  '060252': 'escobar', // Escobar
  '060260': 'esteban-echeverria', // Esteban Echeverría
  '060266': 'exaltacion-de-la-cruz', // Exaltación de la Cruz
  '060270': 'ezeiza', // Ezeiza
  '060274': 'florencio-varela', // Florencio Varela
  '060277': 'florentino-ameghino', // Florentino Ameghino
  '060280': 'general-alvarado', // General Alvarado
  '060287': 'general-alvear', // General Alvear
  '060294': 'general-arenales', // General Arenales
  '060301': 'general-belgrano', // General Belgrano
  '060308': 'general-guido', // General Guido
  '060315': 'general-juan-madariaga', // General Juan Madariaga
  '060322': 'general-la-madrid', // General La Madrid
  '060329': 'general-las-heras', // General Las Heras
  '060336': 'general-lavalle', // General Lavalle
  '060343': 'general-paz', // General Paz
  '060351': 'general-pinto', // General Pinto
  '060357': 'general-pueyrredon', // General Pueyrredón
  '060364': 'general-rodriguez', // General Rodríguez
  '060371': 'general-san-martin', // General San Martín
  '060385': 'general-viamonte', // General Viamonte
  '060392': 'general-villegas', // General Villegas
  '060399': 'guamini', // Guaminí
  '060406': 'hipolito-yrigoyen', // Hipólito Yrigoyen
  '060408': 'hurlingham', // Hurlingham
  '060410': 'ituzaingo', // Ituzaingó
  '060412': 'jose-c-paz', // José C. Paz
  '060413': 'junin', // Junín
  '060420': 'la-costa', // La Costa
  '060427': 'la-matanza', // La Matanza
  '060434': 'lanus', // Lanús
  '060441': 'la-plata', // La Plata
  '060448': 'laprida', // Laprida
  '060455': 'las-flores', // Las Flores
  '060462': 'leandro-n-alem', // Leandro N. Alem
  '060466': 'lezama', // Lezama
  '060469': 'lincoln', // Lincoln
  '060476': 'loberia', // Lobería
  '060483': 'lobos', // Lobos
  '060490': 'lomas-de-zamora', // Lomas de Zamora
  '060497': 'lujan', // Luján
  '060505': 'magdalena', // Magdalena
  '060511': 'maipu', // Maipú
  '060515': 'malvinas-argentinas', // Malvinas Argentinas
  '060518': 'mar-chiquita', // Mar Chiquita
  '060525': 'marcos-paz', // Marcos Paz
  '060532': 'mercedes', // Mercedes
  '060539': 'merlo', // Merlo
  '060547': 'monte', // Monte
  '060553': 'monte-hermoso', // Monte Hermoso
  '060560': 'moreno', // Moreno
  '060568': 'moron', // Morón
  '060574': 'navarro', // Navarro
  '060581': 'necochea', // Necochea
  '060588': '9-de-julio', // 9 de Julio
  '060595': 'olavarria', // Olavarría
  '060602': 'patagones', // Patagones
  '060609': 'pehuajo', // Pehuajó
  '060616': 'pellegrini', // Pellegrini
  '060623': 'pergamino', // Pergamino
  '060630': 'pila', // Pila
  '060638': 'pilar', // Pilar
  '060644': 'pinamar', // Pinamar
  '060648': 'presidente-peron', // Presidente Perón
  '060651': 'puan', // Puan
  '060655': 'punta-indio', // Punta Indio
  '060658': 'quilmes', // Quilmes
  '060665': 'ramallo', // Ramallo
  '060672': 'rauch', // Rauch
  '060679': 'rivadavia', // Rivadavia
  '060686': 'rojas', // Rojas
  '060693': 'roque-perez', // Roque Pérez
  '060700': 'saavedra', // Saavedra
  '060707': 'saladillo', // Saladillo
  '060714': 'salto', // Salto
  '060721': 'salliquelo', // Salliqueló
  '060728': 'san-andres-de-giles', // San Andrés de Giles
  '060735': 'san-antonio-de-areco', // San Antonio de Areco
  '060742': 'san-cayetano', // San Cayetano
  '060749': 'san-fernando', // San Fernando
  '060756': 'san-isidro', // San Isidro
  '060760': 'san-miguel', // San Miguel
  '060763': 'san-nicolas', // San Nicolás
  '060770': 'san-pedro', // San Pedro
  '060778': 'san-vicente', // San Vicente
  '060784': 'suipacha', // Suipacha
  '060791': 'tandil', // Tandil
  '060798': 'tapalque', // Tapalqué
  '060805': 'tigre', // Tigre
  '060812': 'tordillo', // Tordillo
  '060819': 'tornquist', // Tornquist
  '060826': 'trenque-lauquen', // Trenque Lauquen
  '060833': 'tres-arroyos', // Tres Arroyos
  '060840': 'tres-de-febrero', // Tres de Febrero
  '060847': 'tres-lomas', // Tres Lomas
  '060854': '25-de-mayo', // 25 de Mayo
  '060861': 'vicente-lopez', // Vicente López
  '060868': 'villa-gesell', // Villa Gesell
  '060875': 'villarino', // Villarino
  '060882': 'zarate', // Zárate
};
