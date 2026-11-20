SELECT birth_surname,
age
COUNT(*) as count 
FROM residents 
GROUP BY birth_surname 
ORDER BY count DESC 
