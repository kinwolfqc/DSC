Remove-Module DscConfiguration -Force -ErrorAction SilentlyContinue
Import-Module -Name $PSScriptRoot\DscConfiguration.psd1 -Force -ErrorAction Stop

describe 'how Resolve-DscConfigurationProperty responds' {
    $ConfigurationData = @{
        AllNodes = @();
        SiteData = @{ NY = @{ PullServerPath = 'ConfiguredBySite' } };
        Services = @{};
        Applications = @{};
    }

    context 'when a node has an override for a site property' {
        $Node = @{
            Name = 'TestBox'
            Location = 'NY'
            PullServerPath = 'ConfiguredByNode'
        }

        $result = Resolve-DscConfigurationProperty -Node $Node -PropertyName 'PullServerPath'

        it "should return the node's override" {
            $result | should be 'ConfiguredByNode'
        }
    }

    context 'when a node does not override the site property' {
        $Node = @{
            Name = 'TestBox'
            Location = 'NY'
        }

        $result = Resolve-DscConfigurationProperty -Node $Node -PropertyName 'PullServerPath'
        it "should return the site's default value" {
            $result | should be 'ConfiguredBySite'
        }
    }

    context 'when a specific site does not have the property but the base configuration data does' {
        $ConfigurationData.SiteData = @{
            All = @{ PullServerPath = 'ConfiguredByDefault' }
            NY = @{ PullServerPath = 'ConfiguredBySite' }
        }

        $Node = @{
            Name = 'TestBox'
            Location = 'OR'
        }

        $result = Resolve-DscConfigurationProperty -Node $Node -PropertyName 'PullServerPath'
        it "should return the site's default value" {
            $result | should be 'ConfiguredByDefault'
        }
    }
}

describe 'how Resolve-DscConfigurationProperty (services) responds' {
    $ConfigurationData = @{AllNodes = @(); SiteData = @{} ; Services = @{}; Applications = @{}}

    $ConfigurationData.Services = @{
        MyTestService = @{
            Nodes = @('TestBox')
            DataSource = 'MyDefaultValue'
        }
    }

    context 'when a default value is supplied for a service and node has a property override' {

        $Node = @{
            Name = 'TestBox'
            Location = 'NY'
            Services = @{
                MyTestService = @{
                    DataSource = 'MyCustomValue'
                }
            }
        }

        $result = Resolve-DscConfigurationProperty -Node $Node -PropertyName DataSource

        it 'should return the override from the node' {
            $result | should be 'MyCustomValue'

        }
    }

    context 'when a site level override is present' {
        $ConfigurationData.SiteData = @{
            NY = @{
                Services = @{
                    MyTestService = @{
                        DataSource = 'MySiteValue'
                    }
                }
            }
        }
        $Node = @{
            Name = 'TestBox'
            Location = 'NY'
        }

        $result = Resolve-DscConfigurationProperty -Node $Node -PropertyName DataSource

        it 'should return the override from the site' {
            $result | should be 'MySiteValue'
        }
    }

    context 'when no node or site level override is present' {
        $ConfigurationData.Services = @{
            MyTestService = @{
                Nodes = @('TestBox')
                DataSource = 'MyDefaultValue'
            }
        }
        $ConfigurationData.SiteData = @{
            All = @{ DataSource = 'NotMyDefaultValue'}
            NY = @{
                Services = @{
                    MyTestService = @{}
                }
            }
        }
        $Node = @{
            Name = 'TestBox'
            Location = 'NY'
        }

        $result = Resolve-DscConfigurationProperty -Node $Node -PropertyName DataSource

        it 'should return the default value from the service' {
            $result | should be 'MyDefaultValue'

        }
    }

    context 'when no service default is specified' {

        $Node = @{
            Name = 'TestBox'
            Location = 'NY'
            MissingFromFirstServiceConfig = 'FromNodeWithoutService'
        }

        $result = Resolve-DscConfigurationProperty -Node $Node -PropertyName MissingFromFirstServiceConfig
        it 'should fall back to checking for the parameter outside of Services' {
            $result | should be 'FromNodeWithoutService'
        }
    }

    context 'When multiple services exist, but only one contains the desired property' {
        $ConfigurationData.Services = @{
            MyTestService = @{
                Nodes = @('TestBox')
            }
            MySecondTestService = @{
                Nodes = @('TestBox')
                MissingFromFirstServiceConfig = 'FromSecondServiceConfig'
            }
        }
        $Node = @{
            Name = 'TestBox'
            Location = 'NY'
        }

        $result = Resolve-DscConfigurationProperty -Node $Node -PropertyName MissingFromFirstServiceConfig

        it 'should retrieve the parameter from the second service' {
            $result | should be 'FromSecondServiceConfig'
        }
    }
}

Describe 'Resolving multiple values' {
    $ConfigurationData = @{
        AllNodes = @();

        Services = @{
            TestService1 = @{
                ServiceLevel1 = @{
                    Property = 'Service Value'
                }

                NodeLevel1 = @{
                    Property = 'Service Value'
                }

                Nodes = @(
                    'TestNode'
                )
            }

            TestService2 = @{
                ServiceLevel1 = @{
                    Property = 'Service Value'
                }

                NodeLevel1 = @{
                    Property = 'Service Value'
                }

                Nodes = @(
                    'TestNode'
                )
            }

            BogusService = @{
                ServiceLevel1 = @{
                    Property = 'Should Not Resolve'
                }

                Nodes = @()
            }
        }

        SiteData = @{
            All = @{
                NodeLevel1 = @{
                    Property = 'Global Value'
                }
            }

            NY = @{
                NodeLevel1 = @{
                    Property = 'Site Value'
                }
            }
        }
    }

    $Node = @{
        Name = 'TestNode'
        Location = 'NY'

        NodeLevel1 = @{
            Property = 'Node Value'
        }
    }

    It 'Throws an error if multiple services return a value and command is using default behavior' {
        $scriptBlock = { Resolve-DscConfigurationProperty -Node $Node -PropertyName 'ServiceLevel1\Property' }
        $scriptBlock | Should Throw 'More than one result was returned'
    }

    It 'Returns the proper results for multiple services' {
        $scriptBlock = { Resolve-DscConfigurationProperty -Node $Node -PropertyName 'ServiceLevel1\Property' -MultipleResultBehavior AllowMultipleResultsFromSingleScope }
        $scriptBlock | Should Not Throw

        $result = (& $scriptBlock) -join ', '
        $result | Should Be 'Service Value, Service Value'
    }

    It 'Returns the property results for all scopes' {
        $scriptBlock = { Resolve-DscConfigurationProperty -Node $Node -PropertyName 'NodeLevel1\Property' -MultipleResultBehavior AllValues }
        $scriptBlock | Should Not Throw

        $result = (& $scriptBlock) -join ', '
        $result | Should Be 'Service Value, Service Value, Node Value, Site Value, Global Value'
    }
}