# Class: datadog_agent::ubuntu
#
# This class contains the DataDog agent installation mechanism for Debian derivatives
#

class datadog_agent::ubuntu(
  Integer $agent_major_version = $datadog_agent::params::default_agent_major_version,
  String $agent_version = $datadog_agent::params::agent_version,
  Optional[String] $agent_repo_uri = undef,
  String $release = $datadog_agent::params::apt_default_release,
  Boolean $skip_apt_key_trusting = false,
  String $agent_flavor = $datadog_agent::params::package_name,
  Optional[String] $apt_trusted_d_keyring = '/etc/apt/trusted.gpg.d/datadog-archive-keyring.gpg',
  Optional[String] $apt_usr_share_keyring = '/usr/share/keyrings/datadog-archive-keyring.gpg',
  Optional[Hash[String, String]] $apt_default_keys = {
    'DATADOG_APT_KEY_CURRENT.public'           => 'https://keys.datadoghq.com/DATADOG_APT_KEY_CURRENT.public',
    '5F1E256061D813B125E156E8E6266D4AC0962C7D' => 'https://keys.datadoghq.com/DATADOG_APT_KEY_C0962C7D.public',
    'D75CEA17048B9ACBF186794B32637D44F14F620E' => 'https://keys.datadoghq.com/DATADOG_APT_KEY_F14F620E.public',
    'A2923DFF56EDA6E76E55E492D3A80E30382E94DE' => 'https://keys.datadoghq.com/DATADOG_APT_KEY_382E94DE.public',
  },
) inherits datadog_agent::params {

  if $agent_version =~ /^[0-9]+\.[0-9]+\.[0-9]+((?:~|-)[^0-9\s-]+[^-\s]*)?$/ {
    $platform_agent_version = "1:${agent_version}-1"
  }
  else {
    $platform_agent_version = $agent_version
  }

  case $agent_major_version {
    5 : { $repos = 'main' }
    6 : { $repos = '6' }
    7 : { $repos = '7' }
    default: { fail('invalid agent_major_version') }
  }

  if !$skip_apt_key_trusting {
    stdlib::ensure_packages(['gnupg'])

    $apt_key_paths = $apt_default_keys.keys.map |String $key_fingerprint| {
      "/tmp/${key_fingerprint}"
    }

    $apt_default_keys.each |String $key_fingerprint, String $key_url| {
      $key_path = "/tmp/${key_fingerprint}"

      file { $key_path:
        owner  => root,
        group  => root,
        mode   => '0600',
        source => $key_url,
        notify => Exec['build Datadog APT keyring'],
      }
    }

    exec { 'build Datadog APT keyring':
      command     => "/bin/cat ${apt_key_paths.join(' ')} | /usr/bin/gpg --dearmor --yes --output ${apt_usr_share_keyring}",
      refreshonly => true,
      require     => [
        Package['gnupg'],
        File[$apt_key_paths],
      ],
    }

    exec { 'ensure Datadog APT keyring exists':
      command => "/bin/cat ${apt_key_paths.join(' ')} | /usr/bin/gpg --dearmor --yes --output ${apt_usr_share_keyring}",
      unless  => "/usr/bin/test -s ${apt_usr_share_keyring} && /usr/bin/gpg --no-default-keyring --keyring ${apt_usr_share_keyring} --list-keys >/dev/null 2>&1",
      require => [
        Package['gnupg'],
        File[$apt_key_paths],
      ],
    }

    file { $apt_usr_share_keyring:
      ensure  => file,
      owner   => root,
      group   => root,
      mode    => '0644',
      require => [
        Exec['build Datadog APT keyring'],
        Exec['ensure Datadog APT keyring exists'],
      ],
    }

    if ($facts['os']['name'] == 'Ubuntu' and versioncmp($facts['os']['release']['full'], '16') == -1) or
      ($facts['os']['name'] == 'Debian' and versioncmp($facts['os']['release']['full'], '9') == -1) {
      file { $apt_trusted_d_keyring:
        mode   => '0644',
        source => "file://${apt_usr_share_keyring}",
      }
    }
  }

  if ($agent_repo_uri != undef) {
    $location = $agent_repo_uri
  } else {
    $location = "[signed-by=${apt_usr_share_keyring}] https://apt.datadoghq.com/"
  }

  apt::source { 'datadog-beta':
    ensure => absent,
  }

  apt::source { 'datadog5':
    ensure => absent,
  }

  apt::source { 'datadog6':
    ensure => absent,
  }

  apt::source { 'datadog':
    comment  => 'Datadog Agent Repository',
    location => $location,
    release  => $release,
    repos    => $repos,
    require  => File[$apt_usr_share_keyring],
  }

  package { 'datadog-agent-base':
    ensure => absent,
    before => Package[$agent_flavor],
  }

  package { $agent_flavor:
    ensure  => $platform_agent_version,
    require => [Apt::Source['datadog'],
      Class['apt::update']],
  }

  package { 'datadog-signing-keys':
    ensure  => 'latest',
    require => [Apt::Source['datadog'],
      Class['apt::update']],
  }
}