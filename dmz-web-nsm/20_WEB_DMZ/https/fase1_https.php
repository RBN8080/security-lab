<?php
/* HTTPS - Fase 1: publicar la DMZ (WordPress 10.10.20.40:443) en la WAN de pfSense.
   Anade UN port-forward WAN tcp/443 -> 10.10.20.40:443 con pase incorporado.
   Idempotente: si ya existe uno 'Costura3-HTTPS', no duplica. */
require_once("config.inc");
require_once("functions.inc");
require_once("filter.inc");
require_once("util.inc");

$rules = config_get_path('nat/rule', []);
foreach ($rules as $r) {
    if (isset($r['descr']) && strpos($r['descr'], 'Costura3-HTTPS') !== false) {
        echo "YA-EXISTE: un port-forward 'Costura3-HTTPS' ya esta presente; no anado duplicado.\n";
        exit(0);
    }
}

$pf = array(
    'source'            => array('any' => ''),
    'destination'       => array('network' => 'wanip', 'port' => '443'),
    'protocol'          => 'tcp',
    'interface'         => 'wan',
    'ipprotocol'        => 'inet',
    'target'            => '10.10.20.40',
    'local-port'        => '443',
    'descr'             => 'Costura3-HTTPS 443 -> DMZ WordPress',
    'associated-rule-id'=> 'pass',
);
$rules[] = $pf;
config_set_path('nat/rule', $rules);

write_config("Costura3-HTTPS: port-forward WAN tcp/443 -> 10.10.20.40 (publicar DMZ, HTTPS)");
filter_configure_sync();

echo "OK: port-forward anadido (WAN tcp/443 -> 10.10.20.40:443) y filtro recargado.\n";
