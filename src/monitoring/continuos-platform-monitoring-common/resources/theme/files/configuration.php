<?php

/*
 * Dashboard "Business Process": first pane of the dashboard, the page opened
 * after the login (Icinga Web has no landing page setting, it always redirects
 * to /icingaweb2/dashboard). Lower priority = first pane, the Icinga DB panes
 * start from 50. Shown to the roles with the "module/pagopa" permission
 * (roles.ini, icinga-configure.sh) and "module/businessprocess"
 */

/** @var \Icinga\Application\Modules\Module $this */

$this->dashboard(N_('Business Process'), ['priority' => 10])
    ->add(N_('Business Process'), 'businessprocess', 10);
