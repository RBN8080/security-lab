<?php
/* Costura 3 - Paso previo: cerrar la SALIDA de la DMZ a internet mientras la web este expuesta.
   DESACTIVA (no borra) las reglas de la DMZ 'salida web' tcp/80 y tcp/443 (tracker 1791590555 y 1791590556).
   Las entradas a la web siguen funcionando (las respuestas van por estado).
   Uso:  php -f costura3_cerrar_salida_dmz.php            -> cerrar (desactivar las dos)
         php -f costura3_cerrar_salida_dmz.php revertir   -> volver a abrir (ventana de actualizaciones)
   Idempotente. Despues recargar el filtro con /etc/rc.filter_configure_sync
   Otra marcha atras: GUI Firewall > Rules > DMZ, o consola opcion 15. */
require_once("config.inc");
require_once("functions.inc");
require_once("util.inc");

$revertir = (isset($argv[1]) && $argv[1] === 'revertir');
$objetivo = array('1791590555', '1791590556');
$rules = config_get_path('filter/rule', []);
$cambios = 0;
foreach ($rules as $i => $r) {
    if (isset($r['tracker']) && in_array($r['tracker'], $objetivo)) {
        $desactivada = isset($r['disabled']);
        if ($revertir && $desactivada) {
            unset($rules[$i]['disabled']);
            echo "ACTIVO: {$r['tracker']} {$r['descr']}\n";
            $cambios++;
        } elseif (!$revertir && !$desactivada) {
            $rules[$i]['disabled'] = '';
            echo "DESACTIVO: {$r['tracker']} {$r['descr']}\n";
            $cambios++;
        } else {
            echo "SIN-CAMBIO: {$r['tracker']} {$r['descr']}\n";
        }
    }
}

if ($cambios > 0) {
    config_set_path('filter/rule', $rules);
    $motivo = $revertir ? "Costura3: reabrir salida DMZ tcp/80 y tcp/443 (ventana de actualizaciones)"
                        : "Costura3: cerrar salida DMZ a internet (desactivar pass tcp/80 y tcp/443 de la DMZ)";
    write_config($motivo);
    echo "OK: {$cambios} regla(s) cambiada(s); falta recargar el filtro.\n";
} else {
    echo "SIN-CAMBIOS\n";
}
