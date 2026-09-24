WITH records AS(
  SELECT records.arrayvalue as sig
  FROM [audit-logs-input]
  CROSS APPLY GetArrayElements(records) AS records
)

--SELECT udf.parseJson(sig.LogMessage)
SELECT sig.LogMessage
INTO [audit-logs-output]
FROM records
WHERE sig.LogMessage.audit='true'