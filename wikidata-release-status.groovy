#!/usr/bin/env groovy

/*
 * This groovy script checks for latest truthy and lexemes downloads from Wikidata.
 * Outputs the result as JSON using Google's Gson library.
 *
 * Usage: groovy check-latest-wikidata.sh [--since YYYYMMDD]
 *   --since YYYYMMDD  Only include entries after the given date (exclusive)
 *                     Results sorted chronologically (oldest first).
 *                     Without this flag, results sorted reverse chronologically (newest first).
 */

@Grab(group='org.jsoup', module='jsoup', version='1.16.1')
@Grab(group='com.google.code.gson', module='gson', version='2.10.1')
import org.jsoup.Jsoup
import com.google.gson.GsonBuilder
import com.google.gson.JsonObject
import com.google.gson.JsonArray
import groovy.transform.Field
import java.time.LocalDate
import java.time.format.DateTimeFormatter

@Field def dateFormatter = DateTimeFormatter.ofPattern("yyyyMMdd")

def parseArgs(String[] args) {
    def since = null
    for (int i = 0; i < args.length; i++) {
        if (args[i] == "--since" && i + 1 < args.length) {
            since = args[i + 1]
            break
        }
    }
    return since
}

def findAllDumps(JsonObject outJsonObject, List<String> baseNames, LocalDate since) {
    def baseUrl = 'https://dumps.wikimedia.org/wikidatawiki/entities/'
    def indexPage = Jsoup.connect(baseUrl).get()

    def dateDirs = indexPage.select("a[href~=[0-9]{8}/]")
        .collect { it.text().replace("/", "") }
        .findAll { it ==~ /\d{8}/ }
        .collect { LocalDate.parse(it, dateFormatter) }
        .sort()

    for (date in dateDirs) {
        if (since != null && !date.isAfter(since)) {
            continue
        }

        def dateStr = date.format(dateFormatter)
        def subUrl = "${baseUrl}${dateStr}/"
        def subPage = Jsoup.connect(subUrl).get()

        baseNames.each { baseName ->
            def expectedFile = "wikidata-${dateStr}-${baseName}.nt.bz2"
            def found = subPage.select("a[href=${expectedFile}]")

            if (!found.isEmpty()) {
                JsonObject r = new JsonObject()
                r.addProperty("date", dateStr)
                r.addProperty("url", "${subUrl}${expectedFile}")
                outJsonObject.getAsJsonArray(baseName).add(r)
            }
        }
    }
}

def since = parseArgs(args)
def sinceDate = since != null ? LocalDate.parse(since, dateFormatter) : null

def baseNames = ["truthy-BETA", "lexemes-BETA"]

def jsonObject = new JsonObject()
baseNames.each { jsonObject.add(it, new JsonArray()) }

findAllDumps(jsonObject, baseNames, sinceDate)

def gson = new GsonBuilder().setPrettyPrinting().create()
println gson.toJson(jsonObject)

