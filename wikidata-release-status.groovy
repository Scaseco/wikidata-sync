#!/usr/bin/env groovy

/*
 * This groovy script checks for latest truthy and lexemes downloads from Wikidata.
 * Outputs the result as JSON using Google's Gson library.
 *
 * Usage: wikidata-release-status.groovy [baseUrl] [--since YYYYMMDD]
 *   baseUrl           Base URL for Wikidata dumps (default: https://dumps.wikimedia.org/wikidatawiki/entities/)
 *   --since YYYYMMDD  Only include entries after the given date (exclusive)
 *                     Results sorted chronologically (oldest first).
 *                     Without this flag, results sorted reverse chronologically (newest first).
 */

@Grab(group='org.jsoup', module='jsoup', version='1.16.1')
@Grab(group='com.google.code.gson', module='gson', version='2.10.1')
@Grab(group='info.picocli', module='picocli-groovy', version='4.7.7')
import org.jsoup.Jsoup
import com.google.gson.GsonBuilder
import com.google.gson.JsonObject
import com.google.gson.JsonArray
import groovy.transform.Field
import picocli.groovy.PicocliScript
import picocli.CommandLine.Parameters
import picocli.CommandLine.Option
import java.time.LocalDate
import java.time.format.DateTimeFormatter

@PicocliScript

@Field def dateFormatter = DateTimeFormatter.ofPattern("yyyyMMdd")

@Option(names = ["--since"], description = "Only include entries after the given date (exclusive)")
@Field String since

@Parameters(index = "0", defaultValue = "https://dumps.wikimedia.org/wikidatawiki/entities/", description = "Base URL for Wikidata dumps")
@Field String baseUrl

def findAllDumps(JsonObject outJsonObject, List<String> baseNames, String baseUrl, LocalDate since) {
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

def sinceDate = since != null ? LocalDate.parse(since, dateFormatter) : null

def baseNames = ["truthy-BETA", "lexemes-BETA"]

def jsonObject = new JsonObject()
baseNames.each { jsonObject.add(it, new JsonArray()) }

findAllDumps(jsonObject, baseNames, baseUrl, sinceDate)

def gson = new GsonBuilder().setPrettyPrinting().create()
println gson.toJson(jsonObject)

