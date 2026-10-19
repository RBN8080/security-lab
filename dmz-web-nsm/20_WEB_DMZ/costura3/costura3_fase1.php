<?php
/* Costura 3 - Fase 1: publicar la DMZ (WordPress 10.10.20.40:80) en la WAN de pfSense.
   Anade UN port-forward WAN tcp/80 -> 10.10.20.40:80 con pase incorporado.
   Idempotente: si ya existe uno 'Costura3', no duplica. */
require_once("config.inc");
require_once("functions.inc");
require_once("filter.inc");
require_once("util.inc");

$rules = config_get_path('nat/rule', []);
foreach ($rules as $r) {
    if (isset($r['descr']) && strpos($r['descr'], 'Costura3') !== false) {
        echo "YA-EXISTE: un port-forward 'Costura3' ya esta presente; no anado duplicado.\n";
        exit(0);
    }
}

$pf = array(
    'source'            => array('any' => ''),
    'destination'       => array('network' => 'wanip', 'port' => '80'),
    'protocol'          => 'tcp',
    'interface'         => 'wan',
    'ipprotocol'        => 'inet',
    'target'            => '10.10.20.40',
    'local-port'        => '80',
    'descr'             => 'Costura3 Fase1 HTTP 80 -> DMZ WordPress',
    'associated-rule-id'=> 'pass',
);
$rules[] = $pf;
config_set_path('nat/rule', $rules);

write_config("Costura3 Fase1: port-forward WAN tcp/80 -> 10.10.20.40 (publicar DMZ, HTTP)");
filter_configure_sync();

echo "OK: port-forward anadido (WAN tcp/80 -> 10.10.20.40:80) y filtro recargado.\n";
