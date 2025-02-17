$query = @"
<PUT_YOUR_QUERY_HERE>
"@
Import-Module Az.ResourceGraph
Search-AzGraph -Query $query
